import XCTest
import TextBuffer
@testable import TextRope

final class SendableRopeBufferConcurrencyTests: XCTestCase {

    func testTaskGroupParallelReplace() async throws {
        let template = SendableRopeBuffer("Hello, NAME!")

        let results = await withTaskGroup(
            of: (Int, SendableRopeBuffer).self,
            returning: [(Int, SendableRopeBuffer)].self
        ) { group in
            for i in 0..<1000 {
                var buffer = template
                group.addTask {
                    try! buffer.replace(
                        range: NSRange(location: 7, length: 4),
                        with: "User\(i)"
                    )
                    return (i, buffer)
                }
            }
            var collected: [(Int, SendableRopeBuffer)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.count, 1000)
        for (i, buffer) in results {
            XCTAssertEqual(buffer.content, "Hello, User\(i)!")
        }
    }

    /// Concurrent COW coverage at `SendableRopeBuffer` level on a height-3 rope (DEF-008).
    ///
    /// The single-leaf `testTaskGroupParallelReplace` above only exercises
    /// `TextRope.ensureUnique()` at the root; this test's 72-leaf template makes concurrent
    /// path-copying descend through two shared inner levels, and the buffer adds a per-copy
    /// `OperationLog` on top. Each task copies the shared template *inside* its own task body
    /// — copying in the spawning loop would serialize part of the retain traffic on the
    /// parent — and replaces a distinct range in its own subtree. The class must stay
    /// un-isolated (no `@MainActor`): actor isolation would serialize the child tasks and no
    /// uniqueness check would ever be contended. Whether the tasks truly run in parallel is
    /// bounded by the cooperative pool's width (`activeProcessorCount`).
    ///
    /// Developer-local ThreadSanitizer verification (deliberately not a CI gate — the repo
    /// has no CI configuration):
    ///
    ///     swift test --sanitize=thread --filter SendableRopeBufferConcurrencyTests
    ///
    /// A TSan report on `TextRope.Node` fields or `swift_retain`/`swift_release` of a shared
    /// node means the COW discipline is broken; unsanitized, the same breakage surfaces as
    /// content corruption in the oracle assertions below.
    func testTaskGroupParallelReplaceOnMultiLevelRope() async throws {
        let blocks = (0..<72).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2047) + "\n" }
        let original = blocks.joined()
        let template = SendableRopeBuffer(original)
        XCTAssertEqual(
            Int(template.rope.root.height), 3,
            "test assumes 72 full leaves under two levels of inner nodes; a chunking or branching change would silently shrink this to a shallower, weaker case"
        )

        let taskCount = 64
        // Stride past the 2048-unit leaf width so consecutive tasks land in different
        // leaves, inner children, and height-2 subtrees; +17 keeps offsets off leaf seams.
        let offsets = (0..<taskCount).map { $0 * 2304 + 17 }
        XCTAssertLessThan(offsets[taskCount - 1] + 4, template.range.length)

        let results = await withTaskGroup(
            of: (offset: Int, marker: String, content: String).self,
            returning: [(offset: Int, marker: String, content: String)].self
        ) { group in
            for (i, offset) in offsets.enumerated() {
                group.addTask {
                    var local = template
                    try! local.replace(range: NSRange(location: offset, length: 4), with: "[task \(i)]")
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
            let start = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: result.offset)
            let end = oracle.utf16.index(start, offsetBy: 4)
            oracle.replaceSubrange(start..<end, with: result.marker)
            XCTAssertEqual(result.content, oracle, "task replacing at offset \(result.offset) must observe only its own mutation")
        }
        XCTAssertEqual(template.content, original, "the shared template must be unchanged after all tasks complete")
    }

    func testUndoWorksAfterCrossIsolationTransfer() async throws {
        var buffer = SendableRopeBuffer("original")
        try buffer.replace(range: NSRange(location: 0, length: 8), with: "modified")

        let snapshot = buffer
        let undone: SendableRopeBuffer = await Task.detached {
            var b = snapshot
            _ = b.undo()
            return b
        }.value

        XCTAssertEqual(undone.content, "original")
        XCTAssertEqual(buffer.content, "modified")
    }

    func testParallelMutationsAreIndependent() async throws {
        var base = SendableRopeBuffer("base")
        try base.insert(" text", at: 4)

        let results = await withTaskGroup(
            of: String.self,
            returning: [String].self
        ) { group in
            for i in 0..<100 {
                let snapshot = base
                group.addTask {
                    var local = snapshot
                    try! local.insert(" \(i)", at: local.range.length)
                    return local.content
                }
            }
            var collected: [String] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.count, 100)
        XCTAssertEqual(base.content, "base text")

        for result in results {
            XCTAssertTrue(result.hasPrefix("base text "))
        }
    }
}
