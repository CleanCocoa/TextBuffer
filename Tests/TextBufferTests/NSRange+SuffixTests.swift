import XCTest
import Foundation
@testable import TextBuffer

final class NSRangeSuffixTests: XCTestCase {
    func testSuffixAfterLocation() {
        let range = NSRange(location: 2, length: 8)
        XCTAssertEqual(range.suffix(after: 5), NSRange(location: 5, length: 5))
    }

    func testSuffixAfterRange() {
        let range = NSRange(location: 2, length: 8)
        let other = NSRange(location: 3, length: 2)
        XCTAssertEqual(range.suffix(after: other), NSRange(location: 5, length: 5))
    }

    func testSuffixAfterStartReturnsFullRange() {
        let range = NSRange(location: 2, length: 8)
        XCTAssertEqual(range.suffix(after: 2), NSRange(location: 2, length: 8))
    }

    func testSuffixAfterEndReturnsZeroLength() {
        let range = NSRange(location: 2, length: 8)
        XCTAssertEqual(range.suffix(after: 10), NSRange(location: 10, length: 0))
    }

    func testSuffixOfZeroLengthRange() {
        let range = NSRange(location: 5, length: 0)
        XCTAssertEqual(range.suffix(after: 5), NSRange(location: 5, length: 0))
    }

    func testSuffixAfterRangeAtEnd() {
        let range = NSRange(location: 2, length: 8)
        let other = NSRange(location: 7, length: 3)
        XCTAssertEqual(range.suffix(after: other), NSRange(location: 10, length: 0))
    }
}
