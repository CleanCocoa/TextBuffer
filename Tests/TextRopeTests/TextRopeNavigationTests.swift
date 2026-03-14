import XCTest
@testable import TextRope
import Foundation

final class TextRopeNavigationTests: XCTestCase {
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
