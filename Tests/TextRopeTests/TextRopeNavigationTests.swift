import XCTest
@testable import TextRope
import Foundation

final class TextRopeNavigationTests: XCTestCase {
    func testFindLeafInSingleLeafRope() {
        let rope = TextRope("Hello, world!")

        let start = rope.findLeaf(utf16Offset: 0)
        XCTAssertTrue(start.node === rope.root)
        XCTAssertEqual(start.offsetInLeaf, 0)

        let mid = rope.findLeaf(utf16Offset: 7)
        XCTAssertTrue(mid.node === rope.root)
        XCTAssertEqual(mid.offsetInLeaf, 7)

        let end = rope.findLeaf(utf16Offset: 13)
        XCTAssertTrue(end.node === rope.root)
        XCTAssertEqual(end.offsetInLeaf, 13)
    }

    func testFindLeafInMultiLeafRope() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 1200)
        let rope = TextRope(a + b)
        XCTAssertEqual(rope.root.children.count, 2)

        let first = rope.findLeaf(utf16Offset: 600)
        XCTAssertTrue(first.node === rope.root.children[0])
        XCTAssertEqual(first.offsetInLeaf, 600)

        let boundary = rope.findLeaf(utf16Offset: 1200)
        XCTAssertTrue(boundary.node === rope.root.children[1])
        XCTAssertEqual(boundary.offsetInLeaf, 0)

        let last = rope.findLeaf(utf16Offset: 1800)
        XCTAssertTrue(last.node === rope.root.children[1])
        XCTAssertEqual(last.offsetInLeaf, 600)
    }

    func testFindLeafAtEndOfDocumentInMultiLeafRope() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 1200)
        let rope = TextRope(a + b)

        let end = rope.findLeaf(utf16Offset: 2400)
        XCTAssertTrue(end.node === rope.root.children[1])
        XCTAssertEqual(end.offsetInLeaf, 1200)
    }

    func testFindLeafInMultiLevelRope() {
        let blocks = (0..<24).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2048) }
        let rope = TextRope(blocks.joined())
        XCTAssertEqual(Int(rope.root.height), 2)

        let first = rope.findLeaf(utf16Offset: 0)
        XCTAssertEqual(first.node.chunk.first, "a")
        XCTAssertEqual(first.offsetInLeaf, 0)

        let interior = rope.findLeaf(utf16Offset: 10 * 2048 + 100)
        XCTAssertEqual(interior.node.chunk.first, "k")
        XCTAssertEqual(interior.offsetInLeaf, 100)

        let end = rope.findLeaf(utf16Offset: 24 * 2048)
        XCTAssertEqual(end.node.chunk.first, "x")
        XCTAssertEqual(end.offsetInLeaf, 2048)
    }

    private func character(at utf16Offset: Int, in rope: TextRope) -> Character {
        let position = rope.findLeaf(utf16Offset: utf16Offset)
        let utf16View = position.node.chunk.utf16
        let index = utf16View.index(utf16View.startIndex, offsetBy: position.offsetInLeaf)
        return position.node.chunk[index]
    }

    func testUTF16OffsetTranslatesToStringIndexInASCIIChunk() {
        let rope = TextRope("hello")
        XCTAssertEqual(character(at: 0, in: rope), "h")
        XCTAssertEqual(character(at: 3, in: rope), "l")
        XCTAssertEqual(character(at: 4, in: rope), "o")
    }

    func testUTF16OffsetTranslatesToStringIndexInMultiByteChunk() {
        let rope = TextRope("café 你好")
        XCTAssertEqual(character(at: 3, in: rope), "é")
        XCTAssertEqual(character(at: 5, in: rope), "你")
        XCTAssertEqual(character(at: 6, in: rope), "好")
    }

    func testUTF16OffsetTranslatesToStringIndexAtSurrogatePairs() {
        let rope = TextRope("a😀b𝄞c")
        XCTAssertEqual(character(at: 1, in: rope), "😀")
        XCTAssertEqual(character(at: 3, in: rope), "b")
        XCTAssertEqual(character(at: 4, in: rope), "𝄞")
        XCTAssertEqual(character(at: 6, in: rope), "c")
    }

    func testContentInRangeSpanningHeadMiddleAndTailLeaves() {
        let blocks = ["a", "b", "c", "d"].map { String(repeating: $0, count: 2048) }
        let input = blocks.joined()
        let rope = TextRope(input)
        XCTAssertEqual(rope.root.children.count, 4)

        let range = NSRange(location: 1000, length: 6000)
        let expected = (input as NSString).substring(with: range)
        XCTAssertEqual(rope.content(in: range), expected)
    }

    func testContentInRangeOnEmptyRope() {
        let rope = TextRope("")
        XCTAssertEqual(rope.content(in: NSRange(location: 0, length: 0)), "")
    }

    func testContentInDoesNotTriggerCopyOnWrite() {
        let blocks = ["a", "b", "c", "d"].map { String(repeating: $0, count: 2048) }
        let rope = TextRope(blocks.joined())
        let copy = rope

        _ = rope.content(in: NSRange(location: 1000, length: 3000))
        _ = copy.content(in: NSRange(location: 0, length: 8192))

        XCTAssertTrue(rope.root === copy.root)
    }

    func testContentInRangeSingleLeaf() {
        let rope = TextRope("Hello, world!")
        let result = rope.content(in: NSRange(location: 7, length: 5))
        XCTAssertEqual(result, "world")
    }

    func testContentInRangeMultiLeaf() {
        let chunk = String(repeating: "A", count: 2048)
        let input = chunk + "BCDE"
        let rope = TextRope(input)

        let result = rope.content(in: NSRange(location: 2046, length: 6))
        XCTAssertEqual(result, "AABCDE")
    }

    func testContentInRangeAtBoundary() {
        let chunkA = String(repeating: "A", count: 2048)
        let chunkB = String(repeating: "B", count: 2048)
        let rope = TextRope(chunkA + chunkB)

        let resultEnd = rope.content(in: NSRange(location: 2044, length: 4))
        XCTAssertEqual(resultEnd, "AAAA")

        let resultStart = rope.content(in: NSRange(location: 2048, length: 4))
        XCTAssertEqual(resultStart, "BBBB")
    }

    func testContentInRangeMultiByteCharacters() {
        let input = "Hello 🌍🌎🌏 World"
        let rope = TextRope(input)
        let nsString = input as NSString
        let searchRange = nsString.range(of: "🌎")
        let result = rope.content(in: searchRange)
        XCTAssertEqual(result, "🌎")
    }

    func testContentInRangeSurrogatePair() {
        let input = "Music: 𝄞 end"
        let rope = TextRope(input)
        let nsString = input as NSString
        let searchRange = nsString.range(of: "𝄞")
        XCTAssertEqual(searchRange.length, 2)
        let result = rope.content(in: searchRange)
        XCTAssertEqual(result, "𝄞")
    }

    func testContentInRangeEmptyRange() {
        let rope = TextRope("Hello, world!")
        let result = rope.content(in: NSRange(location: 5, length: 0))
        XCTAssertEqual(result, "")
    }

    func testContentInRangeFullRange() {
        let input = "Hello, world!"
        let rope = TextRope(input)
        let result = rope.content(in: NSRange(location: 0, length: input.utf16.count))
        XCTAssertEqual(result, input)
    }
}
