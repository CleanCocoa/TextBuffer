import XCTest
import Foundation
@testable import TextBuffer

final class NSRangePrefixTests: XCTestCase {
    func testPrefixUpToLocation() {
        let range = NSRange(location: 2, length: 8)
        XCTAssertEqual(range.prefix(upTo: 5), NSRange(location: 2, length: 3))
    }

    func testPrefixUpToRange() {
        let range = NSRange(location: 2, length: 8)
        let other = NSRange(location: 5, length: 2)
        XCTAssertEqual(range.prefix(upTo: other), NSRange(location: 2, length: 3))
    }

    func testPrefixUpToStartReturnsZeroLength() {
        let range = NSRange(location: 2, length: 8)
        XCTAssertEqual(range.prefix(upTo: 2), NSRange(location: 2, length: 0))
    }

    func testPrefixUpToEndReturnsFullRange() {
        let range = NSRange(location: 2, length: 8)
        XCTAssertEqual(range.prefix(upTo: 10), NSRange(location: 2, length: 8))
    }

    func testPrefixOfZeroLengthRange() {
        let range = NSRange(location: 5, length: 0)
        XCTAssertEqual(range.prefix(upTo: 5), NSRange(location: 5, length: 0))
    }

    func testPrefixUpToRangeAtStart() {
        let range = NSRange(location: 2, length: 8)
        let other = NSRange(location: 2, length: 3)
        XCTAssertEqual(range.prefix(upTo: other), NSRange(location: 2, length: 0))
    }
}
