import XCTest
import Foundation
@testable import TextRope

final class TextRopeReplaceTests: XCTestCase {
    func testReplaceWithinLeaf() {
        var rope = TextRope("hello world")
        rope.replace(range: NSRange(location: 0, length: 5), with: "greetings")
        XCTAssertEqual(rope.content, "greetings world")
    }

    func testReplaceSpanningLeaves() {
        let chunk = String(repeating: "a", count: 1500)
        let input = chunk + "BRIDGE" + chunk
        var rope = TextRope(input)
        rope.replace(range: NSRange(location: chunk.utf16.count, length: 6), with: "XX")
        XCTAssertEqual(rope.content, chunk + "XX" + chunk)
        verifyTreeInvariants(rope)
    }

    func testReplaceLeavingUnabsorbableUndersizedLeaf() {
        let a = String(repeating: "a", count: 2048)
        let b = String(repeating: "b", count: 2000)
        var rope = TextRope(a + b)
        rope.replace(range: NSRange(location: 2047, length: 1000), with: "XX")
        let expected = String(a.prefix(2047)) + "XX" + String(b.suffix(1001))
        XCTAssertEqual(rope.content, expected)
        verifyTreeInvariants(rope)
    }

    func testReplaceShorterString() {
        var rope = TextRope("hello world")
        rope.replace(range: NSRange(location: 0, length: 5), with: "hi")
        XCTAssertEqual(rope.content, "hi world")
    }

    func testReplaceLongerString() {
        var rope = TextRope("hi world")
        rope.replace(range: NSRange(location: 0, length: 2), with: "hello")
        XCTAssertEqual(rope.content, "hello world")
    }

    func testReplaceEmptyStringIsDelete() {
        var rope = TextRope("hello world")
        rope.replace(range: NSRange(location: 5, length: 6), with: "")
        XCTAssertEqual(rope.content, "hello")
    }

    func testReplaceEmptyRangeIsInsert() {
        var rope = TextRope("helloworld")
        rope.replace(range: NSRange(location: 5, length: 0), with: " ")
        XCTAssertEqual(rope.content, "hello world")
    }

    func testReplaceUpdatesUTF16Count() {
        var rope = TextRope("hello world")
        XCTAssertEqual(rope.utf16Count, 11)
        rope.replace(range: NSRange(location: 0, length: 5), with: "hi")
        XCTAssertEqual(rope.utf16Count, 8)
        XCTAssertEqual(rope.utf16Count, rope.content.utf16.count)
    }

    func testReplacePreservesCOW() {
        var rope = TextRope("hello world")
        let copy = rope
        rope.replace(range: NSRange(location: 0, length: 5), with: "goodbye")
        XCTAssertEqual(copy.content, "hello world")
        XCTAssertEqual(rope.content, "goodbye world")
    }

    func testReplaceMultiByte() {
        let input = "AB\u{1F600}CD"
        var rope = TextRope(input)
        rope.replace(range: NSRange(location: 2, length: 2), with: "!!")
        XCTAssertEqual(rope.content, "AB!!CD")
        XCTAssertEqual(rope.utf16Count, 6)
    }

    func testReplaceEntireContentWithEmptyStringYieldsEmptyRope() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())

        rope.replace(range: NSRange(location: 0, length: rope.utf16Count), with: "")

        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.content, "")
        XCTAssertEqual(rope.utf16Count, 0)
        XCTAssertEqual(rope.utf8Count, 0)
        XCTAssertTrue(rope.root.isLeaf)
    }

    func testReplaceEmptyRangeInsertsAtStartAndEnd() {
        var atStart = TextRope("hello")
        atStart.replace(range: NSRange(location: 0, length: 0), with: ">>")
        XCTAssertEqual(atStart.content, ">>hello")

        var atEnd = TextRope("hello")
        atEnd.replace(range: NSRange(location: 5, length: 0), with: "<<")
        XCTAssertEqual(atEnd.content, "hello<<")
    }

    func testReplaceEmptyRangeWithEmptyStringIsNoOp() {
        var rope = TextRope("hello world")
        rope.replace(range: NSRange(location: 5, length: 0), with: "")
        XCTAssertEqual(rope.content, "hello world")
        XCTAssertEqual(rope.utf16Count, 11)
    }

    func testReplaceASCIIWithEmoji() {
        var rope = TextRope("hello world")
        rope.replace(range: NSRange(location: 0, length: 5), with: "😀🎉")
        XCTAssertEqual(rope.content, "😀🎉 world")
        XCTAssertEqual(rope.utf16Count, 10)
        XCTAssertEqual(rope.utf8Count, "😀🎉 world".utf8.count)
    }

    func testReplaceWithinTextContainingSurrogatePairs() {
        var rope = TextRope("😀b🎉")
        rope.replace(range: NSRange(location: 2, length: 1), with: "𝄞")
        XCTAssertEqual(rope.content, "😀𝄞🎉")
        XCTAssertEqual(rope.utf16Count, 6)
    }

    func testSummaryCorrectAfterReplacesWithNewlinesEmojiAndMultiLeafSpans() {
        var newlines = TextRope("one\ntwo\r\nthree")
        newlines.replace(range: NSRange(location: 3, length: 6), with: "\n\n")
        XCTAssertEqual(newlines.root.summary, TextRope.Summary.of(newlines.content))
        XCTAssertEqual(newlines.root.summary.lines, TextRopeStressTests.newlineCount(in: newlines.content))

        var emoji = TextRope("aébc")
        emoji.replace(range: NSRange(location: 1, length: 2), with: "😀你𝄞")
        XCTAssertEqual(emoji.root.summary, TextRope.Summary.of(emoji.content))

        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var spanning = TextRope(blocks.joined())
        spanning.replace(range: NSRange(location: 1000, length: 5000), with: "line\r\n你😀")
        XCTAssertEqual(spanning.root.summary, TextRope.Summary.of(spanning.content))
        verifyTreeInvariants(spanning, context: "multi-leaf replace")
    }

    func testReplaceOnSingleOwnerRopeMutatesInPlace() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        let rootBefore = ObjectIdentifier(rope.root)
        let untouchedBefore = ObjectIdentifier(rope.root.children[2])

        rope.replace(range: NSRange(location: 100, length: 10), with: "XYZ")

        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
        XCTAssertEqual(ObjectIdentifier(rope.root.children[2]), untouchedBefore)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(rope.content))
    }
}
