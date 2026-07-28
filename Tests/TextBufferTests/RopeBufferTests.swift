import XCTest
import TextBuffer

final class RopeBufferTests: XCTestCase {
    func testContent() {
        let string = "Test string here"
        XCTAssertEqual(RopeBuffer(string).content, string)
    }

    func testRange() {
        XCTAssertEqual(RopeBuffer("").range,
                       .init(location: 0, length: 0))
        XCTAssertEqual(RopeBuffer("a").range,
                       .init(location: 0, length: 1))
        XCTAssertEqual(RopeBuffer("hello\n\nworld").range,
                       .init(location: 0, length: 12))
    }

    func testInsert() throws {
        let buffer = RopeBuffer("hello")
        try buffer.insert(" world", at: 5)
        XCTAssertEqual(buffer.content, "hello world")
    }

    func testDelete() throws {
        let buffer = RopeBuffer("hello world")
        try buffer.delete(in: NSRange(location: 5, length: 6))
        XCTAssertEqual(buffer.content, "hello")
    }

    func testReplace() throws {
        let buffer = RopeBuffer("hello world")
        try buffer.replace(range: NSRange(location: 6, length: 5), with: "there")
        XCTAssertEqual(buffer.content, "hello there")
    }

    func testInsertShiftsSelection() throws {
        let buffer = RopeBuffer("hello world")
        buffer.selectedRange = NSRange(location: 6, length: 3)

        assertBufferState(buffer, "hello «wor»ld")

        try buffer.insert("XX", at: 3)

        assertBufferState(buffer, "helXXlo «wor»ld")
    }

    func testDeleteSubtractsSelection() throws {
        let buffer = RopeBuffer("hello world")
        buffer.selectedRange = NSRange(location: 3, length: 5)

        assertBufferState(buffer, "hel«lo wo»rld")

        try buffer.delete(in: NSRange(location: 2, length: 4))

        assertBufferState(buffer, "he«wo»rld")
    }

    func testOutOfRangeThrows() {
        let buffer = RopeBuffer("hello")
        let available = NSRange(location: 0, length: 5)

        assertThrows(
            try buffer.insert("x", at: 6),
            error: BufferAccessFailure.outOfRange(
                location: 6,
                available: available
            )
        )

        assertThrows(
            try buffer.delete(in: NSRange(location: 3, length: 5)),
            error: BufferAccessFailure.outOfRange(
                requested: NSRange(location: 3, length: 5),
                available: available
            )
        )

        assertThrows(
            try buffer.replace(range: NSRange(location: 4, length: 3), with: "x"),
            error: BufferAccessFailure.outOfRange(
                requested: NSRange(location: 4, length: 3),
                available: available
            )
        )
    }

    func testContentInSubrange() throws {
        let buffer = RopeBuffer("hello world")
        let result = try buffer.content(in: NSRange(location: 6, length: 5))
        XCTAssertEqual(result, "world")
    }

    func testSetInsertionLocation() {
        let buffer = RopeBuffer("hello")
        buffer.selectedRange = NSRange(location: 1, length: 3)
        buffer.setInsertionLocation(4)
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 4, length: 0))
    }

    func testLineRangeExpandsToWholeLine() throws {
        let buffer = RopeBuffer("first line\nsecond line\nthird")

        XCTAssertEqual(
            try buffer.lineRange(for: NSRange(location: 13, length: 3)),
            NSRange(location: 11, length: 12)
        )
        XCTAssertEqual(
            try buffer.lineRange(for: NSRange(location: 0, length: 0)),
            NSRange(location: 0, length: 11)
        )
    }

    func testLineRangeThrowsForOutOfBoundsRange() {
        let buffer = RopeBuffer("short")

        assertThrows(
            try buffer.lineRange(for: NSRange(location: 3, length: 9)),
            error: BufferAccessFailure.outOfRange(
                requested: NSRange(location: 3, length: 9),
                available: NSRange(location: 0, length: 5)
            )
        )
    }

    func testModifyingExecutesBlockAndReturnsItsResult() throws {
        let buffer = RopeBuffer("hello world")

        let result = try buffer.modifying(affectedRange: NSRange(location: 0, length: 5)) {
            "block result"
        }

        XCTAssertEqual(result, "block result")
    }

    func testModifyingThrowsForOutOfBoundsRangeWithoutExecutingBlock() {
        let buffer = RopeBuffer("hello")
        var blockExecuted = false

        assertThrows(
            try buffer.modifying(affectedRange: NSRange(location: 2, length: 9)) {
                blockExecuted = true
            },
            error: BufferAccessFailure.outOfRange(
                requested: NSRange(location: 2, length: 9),
                available: NSRange(location: 0, length: 5)
            )
        )
        XCTAssertFalse(blockExecuted)
    }

    func testWordRangeExpandsToWholeWord() throws {
        let buffer = RopeBuffer("hello wonderful world")

        XCTAssertEqual(
            try buffer.wordRange(for: NSRange(location: 8, length: 2)),
            NSRange(location: 6, length: 9)
        )
        XCTAssertEqual(
            try buffer.wordRange(for: NSRange(location: 2, length: 0)),
            NSRange(location: 0, length: 5)
        )
    }

    func testDescriptionShowsInsertionPointWithCaretNotation() {
        let buffer = RopeBuffer("Hello, world!")
        XCTAssertEqual(String(describing: buffer), "ˇHello, world!")

        buffer.setInsertionLocation(5)
        XCTAssertEqual(String(describing: buffer), "Helloˇ, world!")
    }

    func testDescriptionShowsSelectionWithGuillemetNotation() {
        let buffer = RopeBuffer("Hello, world!")
        buffer.select(NSRange(location: 7, length: 5))
        XCTAssertEqual(String(describing: buffer), "Hello, «world»!")
    }

    func testInitCopyingFromMutableStringBuffer() {
        let source = MutableStringBuffer("hello world")
        source.selectedRange = NSRange(location: 6, length: 5)

        let copy = RopeBuffer(copying: source)

        XCTAssertEqual(copy.content, "hello world")
        XCTAssertEqual(copy.selectedRange, NSRange(location: 6, length: 5))
    }

    func testInitCopyingFromRopeBuffer() {
        let source = RopeBuffer("hello world")
        source.selectedRange = NSRange(location: 3, length: 2)

        let copy = RopeBuffer(copying: source)

        XCTAssertEqual(copy.content, "hello world")
        XCTAssertEqual(copy.selectedRange, NSRange(location: 3, length: 2))
    }
}
