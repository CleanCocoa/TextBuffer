import XCTest
@testable import TextRope

final class SummaryTests: XCTestCase {
    func testZeroSummary() {
        let s = TextRope.Summary.zero
        XCTAssertEqual(s.utf8, 0)
        XCTAssertEqual(s.utf16, 0)
        XCTAssertEqual(s.lines, 0)
    }

    func testOfASCII() {
        let s = TextRope.Summary.of("hello")
        XCTAssertEqual(s.utf8, 5)
        XCTAssertEqual(s.utf16, 5)
        XCTAssertEqual(s.lines, 0)
    }

    func testOfWithNewlines() {
        let s = TextRope.Summary.of("a\nb\nc")
        XCTAssertEqual(s.utf8, 5)
        XCTAssertEqual(s.utf16, 5)
        XCTAssertEqual(s.lines, 2)
    }

    func testOfEmoji() {
        let s = TextRope.Summary.of("😀")
        XCTAssertEqual(s.utf8, 4)
        XCTAssertEqual(s.utf16, 2)
        XCTAssertEqual(s.lines, 0)
    }

    func testOfSurrogatePair() {
        let s = TextRope.Summary.of("𝄞")
        XCTAssertEqual(s.utf8, 4)
        XCTAssertEqual(s.utf16, 2)
        XCTAssertEqual(s.lines, 0)
    }

    func testOfCRLF() {
        let s = TextRope.Summary.of("a\r\nb")
        XCTAssertEqual(s.utf8, 4)
        XCTAssertEqual(s.utf16, 4)
        XCTAssertEqual(s.lines, 1)
    }

    func testAdd() {
        var a = TextRope.Summary(utf8: 3, utf16: 3, lines: 1)
        let b = TextRope.Summary(utf8: 5, utf16: 5, lines: 2)
        a.add(b)
        XCTAssertEqual(a.utf8, 8)
        XCTAssertEqual(a.utf16, 8)
        XCTAssertEqual(a.lines, 3)
    }

    func testSubtract() {
        var a = TextRope.Summary(utf8: 8, utf16: 8, lines: 3)
        let b = TextRope.Summary(utf8: 3, utf16: 3, lines: 1)
        a.subtract(b)
        XCTAssertEqual(a.utf8, 5)
        XCTAssertEqual(a.utf16, 5)
        XCTAssertEqual(a.lines, 2)
    }

    func testOfEmpty() {
        let s = TextRope.Summary.of("")
        XCTAssertEqual(s, TextRope.Summary.zero)
    }
}
