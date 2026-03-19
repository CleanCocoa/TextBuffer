import XCTest
@testable import TextRope

final class TextRopeInsertTests: XCTestCase {
    func testInsertAtStart() {
        var rope = TextRope("hello")
        rope.insert("X", at: 0)
        XCTAssertEqual(rope.content, "Xhello")
    }

    func testInsertAtEnd() {
        var rope = TextRope("hello")
        rope.insert("X", at: 5)
        XCTAssertEqual(rope.content, "helloX")
    }

    func testInsertAtMiddle() {
        var rope = TextRope("hello")
        rope.insert("X", at: 2)
        XCTAssertEqual(rope.content, "heXllo")
    }

    func testInsertEmptyString() {
        var rope = TextRope("hello")
        rope.insert("", at: 2)
        XCTAssertEqual(rope.content, "hello")
    }

    func testInsertCausingLeafSplit() {
        var rope = TextRope("a")
        let large = String(repeating: "B", count: 2500)
        rope.insert(large, at: 1)
        XCTAssertEqual(rope.content, "a" + large)
        XCTAssertEqual(rope.utf8Count, 2501)
        verifyTreeInvariants(rope)
    }

    func testInsertMultiByteCharacter() {
        var rope = TextRope("abc")
        rope.insert("\u{1F600}", at: 1)
        XCTAssertEqual(rope.content, "a\u{1F600}bc")
        XCTAssertEqual(rope.utf16Count, 5)
    }

    func testInsertPreservesCOW() {
        var rope = TextRope("hello")
        let copy = rope
        rope.insert("X", at: 0)
        XCTAssertEqual(copy.content, "hello")
        XCTAssertEqual(rope.content, "Xhello")
    }

    func testInsertCascadingSplits() {
        let chunkSize = 2048
        let leafCount = 8 * 8
        let bigString = String(repeating: "A", count: chunkSize * leafCount)
        var rope = TextRope(bigString)
        verifyTreeInvariants(rope)
        let insertContent = String(repeating: "Z", count: chunkSize * 2)
        rope.insert(insertContent, at: 0)
        XCTAssertEqual(rope.content, insertContent + bigString)
        XCTAssertEqual(rope.utf8Count, bigString.utf8.count + insertContent.utf8.count)
        verifyTreeInvariants(rope)
    }

    func testInsertUpdatesUTF16Count() {
        var rope = TextRope("abc")
        XCTAssertEqual(rope.utf16Count, 3)
        rope.insert("de", at: 1)
        XCTAssertEqual(rope.utf16Count, 5)
        rope.insert("\u{1F600}", at: 0)
        XCTAssertEqual(rope.utf16Count, 7)
    }

    func testMultipleInserts() {
        var rope = TextRope("ac")
        rope.insert("b", at: 1)
        XCTAssertEqual(rope.content, "abc")
        rope.insert("d", at: 3)
        XCTAssertEqual(rope.content, "abcd")
        rope.insert("0", at: 0)
        XCTAssertEqual(rope.content, "0abcd")
        rope.insert("X", at: 2)
        XCTAssertEqual(rope.content, "0aXbcd")
    }
}
