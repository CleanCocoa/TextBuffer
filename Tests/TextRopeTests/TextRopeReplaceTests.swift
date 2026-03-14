import XCTest
import Foundation
import TextRope

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
}
