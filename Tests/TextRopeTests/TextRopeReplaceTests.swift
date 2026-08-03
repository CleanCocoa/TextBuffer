import XCTest
import Testing
@testable import TextRope

final class TextRopeReplaceTests: XCTestCase {
    func testReplaceWithinLeaf() {
        var rope = TextRope("hello world")
        rope.replace(range: 0..<5, with: "greetings")
        XCTAssertEqual(rope.content, "greetings world")
    }

    func testReplaceSpanningLeaves() {
        let chunk = String(repeating: "a", count: 1500)
        let input = chunk + "BRIDGE" + chunk
        var rope = TextRope(input)
        rope.replace(range: chunk.utf16.count ..< chunk.utf16.count + 6, with: "XX")
        XCTAssertEqual(rope.content, chunk + "XX" + chunk)
        verifyTreeInvariants(rope)
    }

    func testReplaceLeavingUnabsorbableUndersizedLeaf() {
        let a = String(repeating: "a", count: 2048)
        let b = String(repeating: "b", count: 2000)
        var rope = TextRope(a + b)
        rope.replace(range: 2047..<3047, with: "XX")
        let expected = String(a.prefix(2047)) + "XX" + String(b.suffix(1001))
        XCTAssertEqual(rope.content, expected)
        verifyTreeInvariants(rope)
    }

    func testReplaceShorterString() {
        var rope = TextRope("hello world")
        rope.replace(range: 0..<5, with: "hi")
        XCTAssertEqual(rope.content, "hi world")
    }

    func testReplaceLongerString() {
        var rope = TextRope("hi world")
        rope.replace(range: 0..<2, with: "hello")
        XCTAssertEqual(rope.content, "hello world")
    }

    func testReplaceEmptyStringIsDelete() {
        var rope = TextRope("hello world")
        rope.replace(range: 5..<11, with: "")
        XCTAssertEqual(rope.content, "hello")
    }

    func testReplaceEmptyRangeIsInsert() {
        var rope = TextRope("helloworld")
        rope.replace(range: 5..<5, with: " ")
        XCTAssertEqual(rope.content, "hello world")
    }

    func testReplaceUpdatesUTF16Count() {
        var rope = TextRope("hello world")
        XCTAssertEqual(rope.utf16Count, 11)
        rope.replace(range: 0..<5, with: "hi")
        XCTAssertEqual(rope.utf16Count, 8)
        XCTAssertEqual(rope.utf16Count, rope.content.utf16.count)
    }

    func testReplacePreservesCOW() {
        var rope = TextRope("hello world")
        let copy = rope
        rope.replace(range: 0..<5, with: "goodbye")
        XCTAssertEqual(copy.content, "hello world")
        XCTAssertEqual(rope.content, "goodbye world")
    }

    func testReplaceMultiByte() {
        let input = "AB\u{1F600}CD"
        var rope = TextRope(input)
        rope.replace(range: 2..<4, with: "!!")
        XCTAssertEqual(rope.content, "AB!!CD")
        XCTAssertEqual(rope.utf16Count, 6)
    }

    func testReplaceEntireContentWithEmptyStringYieldsEmptyRope() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())

        rope.replace(range: 0 ..< rope.utf16Count, with: "")

        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.content, "")
        XCTAssertEqual(rope.utf16Count, 0)
        XCTAssertEqual(rope.utf8Count, 0)
        XCTAssertTrue(rope.root.isLeaf)
    }

    func testReplaceEmptyRangeInsertsAtStartAndEnd() {
        var atStart = TextRope("hello")
        atStart.replace(range: 0..<0, with: ">>")
        XCTAssertEqual(atStart.content, ">>hello")

        var atEnd = TextRope("hello")
        atEnd.replace(range: 5..<5, with: "<<")
        XCTAssertEqual(atEnd.content, "hello<<")
    }

    func testReplaceEmptyRangeWithEmptyStringIsNoOp() {
        var rope = TextRope("hello world")
        rope.replace(range: 5..<5, with: "")
        XCTAssertEqual(rope.content, "hello world")
        XCTAssertEqual(rope.utf16Count, 11)
    }

    func testReplaceASCIIWithEmoji() {
        var rope = TextRope("hello world")
        rope.replace(range: 0..<5, with: "😀🎉")
        XCTAssertEqual(rope.content, "😀🎉 world")
        XCTAssertEqual(rope.utf16Count, 10)
        XCTAssertEqual(rope.utf8Count, "😀🎉 world".utf8.count)
    }

    func testReplaceWithinTextContainingSurrogatePairs() {
        var rope = TextRope("😀b🎉")
        rope.replace(range: 2..<3, with: "𝄞")
        XCTAssertEqual(rope.content, "😀𝄞🎉")
        XCTAssertEqual(rope.utf16Count, 6)
    }

    func testSummaryCorrectAfterReplacesWithNewlinesEmojiAndMultiLeafSpans() {
        var newlines = TextRope("one\ntwo\r\nthree")
        newlines.replace(range: 3..<9, with: "\n\n")
        XCTAssertEqual(newlines.root.summary, TextRope.Summary.of(newlines.content))
        XCTAssertEqual(newlines.root.summary.lines, TextRopeStressTests.newlineCount(in: newlines.content))

        var emoji = TextRope("aébc")
        emoji.replace(range: 1..<3, with: "😀你𝄞")
        XCTAssertEqual(emoji.root.summary, TextRope.Summary.of(emoji.content))

        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var spanning = TextRope(blocks.joined())
        spanning.replace(range: 1000..<6000, with: "line\r\n你😀")
        XCTAssertEqual(spanning.root.summary, TextRope.Summary.of(spanning.content))
        verifyTreeInvariants(spanning, context: "multi-leaf replace")
    }

    func testReplaceOnSingleOwnerRopeMutatesInPlace() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        let rootBefore = ObjectIdentifier(rope.root)
        let untouchedBefore = ObjectIdentifier(rope.root.children[2])

        rope.replace(range: 100..<110, with: "XYZ")

        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
        XCTAssertEqual(ObjectIdentifier(rope.root.children[2]), untouchedBefore)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(rope.content))
    }

    /// Pins rope-replace's single-owner scenario. `replace` composes `delete` then `insert`,
    /// so before DEF-003's alias fix in the delete descent this test would have been red on
    /// HEAD: the delete leg path-copied every node below the root despite the single owner.
    func testReplaceOnSingleOwnerMultiLevelRopeKeepsOnPathNodeIdentity() {
        let blocks = (0..<20).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(
            rope.root.children.map(\.children.count), [8, 8, 4],
            "test assumes a height-2 tree of 20 full leaves grouped [8, 8, 4]; a chunking or branching change invalidates the on-path indices below"
        )
        // ObjectIdentifier holds no ownership; a node binding would be a second strong
        // reference and defeat the in-place mutation this test asserts (design D2).
        let rootBefore = ObjectIdentifier(rope.root)
        let onPathInnerBefore = ObjectIdentifier(rope.root.children[0])
        let onPathLeafBefore = ObjectIdentifier(rope.root.children[0].children[0])

        rope.replace(range: 100..<110, with: "xyz")

        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
        XCTAssertEqual(
            ObjectIdentifier(rope.root.children[0]), onPathInnerBefore,
            "inner node on the replace path must be mutated in place when the rope has a single owner"
        )
        XCTAssertEqual(
            ObjectIdentifier(rope.root.children[0].children[0]), onPathLeafBefore,
            "leaf on the replace path must be mutated in place when the rope has a single owner"
        )

        var expected = blocks.joined()
        let start = expected.utf16.index(expected.utf16.startIndex, offsetBy: 100)
        let end = expected.utf16.index(start, offsetBy: 10)
        expected.replaceSubrange(start..<end, with: "xyz")
        XCTAssertEqual(rope.content, expected)
    }

    // MARK: Range<Int> primitive mirrors

    func testReplaceIntRangeWithinLeaf() {
        var rope = TextRope("hello world")
        rope.replace(range: 5..<11, with: " there")
        XCTAssertEqual(rope.content, "hello there")
        XCTAssertEqual(rope.utf16Count, 11)
    }

    func testReplaceIntRangeSpanningLeaves() {
        let chunk = String(repeating: "a", count: 1500)
        let input = chunk + "BRIDGE" + chunk
        var rope = TextRope(input)
        rope.replace(range: 1500..<1506, with: "XX")
        XCTAssertEqual(rope.content, chunk + "XX" + chunk)
        verifyTreeInvariants(rope)
    }

    func testReplaceIntRangeMultiByte() {
        var rope = TextRope("café")
        rope.replace(range: 3..<4, with: "🎉")
        XCTAssertEqual(rope.content, "caf🎉")
        XCTAssertEqual(rope.utf16Count, 5)
    }

    // DEF-006b: degenerate cases specced as observable equivalence.

    func testReplaceIntRangeWithEmptyStringEqualsDeleteAlone() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        let input = blocks.joined()
        var replaced = TextRope(input)
        var deleted = TextRope(input)

        replaced.replace(range: 1000..<6000, with: "")
        deleted.delete(in: 1000..<6000)

        XCTAssertEqual(replaced, deleted)
        XCTAssertEqual(replaced.content, deleted.content)
        XCTAssertEqual(replaced.utf16Count, deleted.utf16Count)
        XCTAssertEqual(replaced.utf8Count, deleted.utf8Count)
        XCTAssertEqual(replaced.root.summary, deleted.root.summary)
        verifyTreeInvariants(replaced)
    }

    func testReplaceIntRangeEmptyRangeEqualsInsertAlone() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        let input = blocks.joined()
        var replaced = TextRope(input)
        var inserted = TextRope(input)

        replaced.replace(range: 3000..<3000, with: "wedge\r\n你😀")
        inserted.insert("wedge\r\n你😀", at: 3000)

        XCTAssertEqual(replaced, inserted)
        XCTAssertEqual(replaced.content, inserted.content)
        XCTAssertEqual(replaced.utf16Count, inserted.utf16Count)
        XCTAssertEqual(replaced.utf8Count, inserted.utf8Count)
        XCTAssertEqual(replaced.root.summary, inserted.root.summary)
        verifyTreeInvariants(replaced)
    }

    func testReplaceIntRangeBothEmptyIsNoOp() {
        var rope = TextRope("hello")
        let rootBefore = ObjectIdentifier(rope.root)

        rope.replace(range: 3..<3, with: "")

        XCTAssertEqual(rope.content, "hello")
        XCTAssertEqual(rope.utf16Count, 5)
        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
    }
}

@Suite struct TextRopeReplaceIntRangePreconditions {
    @Test func `replacing traps when the range end exceeds the document length`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.replace(range: 3..<8, with: "x")
        }
    }

    @Test func `replacing traps for a negative lowerBound`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.replace(range: (-1)..<2, with: "x")
        }
    }

    @Test func `replacing traps for an empty range past the end`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.replace(range: 500..<500, with: "x")
        }
    }
}
