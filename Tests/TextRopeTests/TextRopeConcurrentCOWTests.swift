import XCTest
@testable import TextRope

/// Concurrent copy-on-write coverage for `TextRope` (DEF-008).
///
/// `TextRope` is `Sendable` over a `nonisolated(unsafe) var root` whose `Node` class is not
/// `Sendable`; the value-type wrapper plus the COW discipline is the entire safety argument.
/// These tests exercise that discipline where it is actually contended: path-copying through
/// two levels of shared inner nodes, not just `ensureUnique()` at the root.
///
/// This class must NOT be `@MainActor`-isolated: XCTest's `async` test methods run on the
/// cooperative pool, and actor isolation would serialize every child task, so the copies and
/// uniqueness checks would never actually race. Whether the tasks truly run in parallel is
/// bounded by the cooperative pool's width (`activeProcessorCount`); on a single-core machine
/// they can serialize and the test degrades to its deterministic oracle assertions.
///
/// Developer-local ThreadSanitizer verification (deliberately not a CI gate — the repo has
/// no CI configuration):
///
///     swift test --sanitize=thread --filter TextRopeConcurrentCOWTests
///
/// A TSan report on `TextRope.Node.chunk`, `.children`, `.summary`, or on
/// `swift_retain`/`swift_release` of a shared node means the COW discipline is broken.
/// Without TSan, the same breakage surfaces as content corruption in the per-task oracle
/// assertions below, so an unsanitized run is still meaningful.
final class TextRopeConcurrentCOWTests: XCTestCase {
    /// Each task copies the shared height-3 template *inside* its own task body — copying in
    /// the spawning loop would serialize part of the retain traffic on the parent — and
    /// mutates at its own offset, spread across different height-2 subtrees, inner children,
    /// and leaves, so `Node.ensureUniqueChild(at:)` runs concurrently at two depths against
    /// genuinely shared children.
    func testConcurrentMutationsFromSharedMultiLevelTemplateAreIndependent() async {
        let blocks = (0..<72).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2047) + "\n" }
        let original = blocks.joined()
        let template = TextRope(original)
        XCTAssertEqual(
            Int(template.root.height), 3,
            "test assumes 72 full leaves under two levels of inner nodes; a chunking or branching change would silently shrink this to a shallower, weaker case"
        )

        let taskCount = 64
        // Stride past the 2048-unit leaf width so consecutive tasks land in different
        // leaves, inner children, and height-2 subtrees; +17 keeps offsets off leaf seams.
        let offsets = (0..<taskCount).map { $0 * 2304 + 17 }
        XCTAssertLessThan(offsets[taskCount - 1], template.utf16Count)

        let results = await withTaskGroup(
            of: (offset: Int, marker: String, content: String).self,
            returning: [(offset: Int, marker: String, content: String)].self
        ) { group in
            for (i, offset) in offsets.enumerated() {
                group.addTask {
                    var local = template
                    local.insert("[task \(i)]", at: offset)
                    return (offset, "[task \(i)]", local.content)
                }
            }
            var collected: [(offset: Int, marker: String, content: String)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.count, taskCount)
        for result in results {
            var oracle = original
            let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: result.offset)
            oracle.insert(contentsOf: result.marker, at: idx)
            XCTAssertEqual(result.content, oracle, "task mutating at offset \(result.offset) must observe only its own mutation")
        }
        XCTAssertEqual(template.content, original, "the shared template must be unchanged after all tasks complete")
    }
}
