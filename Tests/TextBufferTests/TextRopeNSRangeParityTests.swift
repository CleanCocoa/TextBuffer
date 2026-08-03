import XCTest
import Testing
import Foundation
import TextBuffer

/// Thin parity coverage for the TextBuffer-target `NSRange` wrappers over TextRope's
/// `Range<Int>` primitives: each wrapper must equal its primitive, and the degenerate
/// encodings only `NSRange` can represent must trap. Behavior depth stays in
/// `TextRopeTests`.
final class TextRopeNSRangeParityTests: XCTestCase {
    /// ASCII, multi-byte BMP, emoji/surrogate pairs, and a multi-leaf rope.
    private let inputs: [String] = [
        "hello world",
        "café résumé 你好",
        "a😀b🎉c𝄞d",
        ["a", "é", "😀", "你"].map { String(repeating: $0, count: 700) }.joined(),
    ]

    /// Snaps `offset` to a scalar boundary so mutation parity ranges never split a pair.
    private func aligned(_ offset: Int, in input: String) -> Int {
        guard offset > 0, offset < input.utf16.count else {
            return max(0, min(offset, input.utf16.count))
        }
        let index = input.utf16.index(input.utf16.startIndex, offsetBy: offset)
        return UTF16.isTrailSurrogate(input.utf16[index]) ? offset - 1 : offset
    }

    private func ranges(in input: String) -> [NSRange] {
        let count = input.utf16.count
        let midStart = aligned(count / 3, in: input)
        let midEnd = aligned(2 * count / 3, in: input)
        return [
            NSRange(location: 0, length: 0),
            NSRange(location: 0, length: count),
            NSRange(location: midStart, length: midEnd - midStart),
        ]
    }

    func testContentParity() {
        for input in inputs {
            let rope = TextRope(input)
            for range in ranges(in: input) {
                XCTAssertEqual(
                    rope.content(in: range),
                    rope.content(in: range.location ..< range.location + range.length),
                    "content(in:) diverged for \(range)"
                )
            }
        }
    }

    func testDeleteParity() {
        for input in inputs {
            for range in ranges(in: input) {
                var viaNSRange = TextRope(input)
                var viaIntRange = TextRope(input)

                viaNSRange.delete(in: range)
                viaIntRange.delete(in: range.location ..< range.location + range.length)

                XCTAssertEqual(viaNSRange, viaIntRange, "delete(in:) diverged for \(range)")
                XCTAssertEqual(viaNSRange.content, viaIntRange.content)
                XCTAssertEqual(viaNSRange.utf16Count, viaIntRange.utf16Count)
            }
        }
    }

    func testReplaceParity() {
        for input in inputs {
            for range in ranges(in: input) {
                var viaNSRange = TextRope(input)
                var viaIntRange = TextRope(input)

                viaNSRange.replace(range: range, with: "wedge\r\n你😀")
                viaIntRange.replace(range: range.location ..< range.location + range.length, with: "wedge\r\n你😀")

                XCTAssertEqual(viaNSRange, viaIntRange, "replace(range:with:) diverged for \(range)")
                XCTAssertEqual(viaNSRange.content, viaIntRange.content)
                XCTAssertEqual(viaNSRange.utf16Count, viaIntRange.utf16Count)
            }
        }
    }
}

/// The wrappers own the `NSRange`-specific validation: `NSNotFound`, negative location,
/// and negative length trap before any forwarding (zero lengths included, so the traps
/// provably come from the wrapper, not from the primitive's bounds checks).
@Suite struct TextRopeNSRangeWrapperPreconditions {
    @Test func `content traps for an NSNotFound location`() async {
        await #expect(processExitsWith: .failure) {
            _ = TextRope("hello").content(in: NSRange(location: NSNotFound, length: 0))
        }
    }

    @Test func `content traps for a negative location`() async {
        await #expect(processExitsWith: .failure) {
            _ = TextRope("hello").content(in: NSRange(location: -1, length: 0))
        }
    }

    @Test func `content traps for a negative length`() async {
        await #expect(processExitsWith: .failure) {
            _ = TextRope("hello").content(in: NSRange(location: 0, length: -1))
        }
    }

    @Test func `delete traps for an NSNotFound location`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.delete(in: NSRange(location: NSNotFound, length: 0))
        }
    }

    @Test func `delete traps for a negative location`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.delete(in: NSRange(location: -1, length: 0))
        }
    }

    @Test func `delete traps for a negative length`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.delete(in: NSRange(location: 0, length: -1))
        }
    }

    @Test func `replace traps for an NSNotFound location`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.replace(range: NSRange(location: NSNotFound, length: 0), with: "x")
        }
    }

    @Test func `replace traps for a negative location`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.replace(range: NSRange(location: -1, length: 0), with: "x")
        }
    }

    @Test func `replace traps for a negative length`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.replace(range: NSRange(location: 0, length: -1), with: "x")
        }
    }
}
