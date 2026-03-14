import XCTest
import TextRope

final class TextRopeTests: XCTestCase {
    func testEmptyRopeIsEmpty() {
        let rope = TextRope()
        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.utf16Count, 0)
        XCTAssertEqual(rope.utf8Count, 0)
    }
}
