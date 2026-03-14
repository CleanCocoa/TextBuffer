import XCTest
import Foundation
@testable import TextBuffer

final class NSRangeExpandedTests: XCTestCase {
    func testExpandUpstreamExtendsStart() {
        let range = NSRange(location: 5, length: 3)
        let outer = NSRange(location: 2, length: 8)
        let result = range.expanded(to: outer, direction: .upstream)
        XCTAssertEqual(result, NSRange(location: 2, length: 6))
    }

    func testExpandDownstreamExtendsEnd() {
        let range = NSRange(location: 5, length: 3)
        let outer = NSRange(location: 2, length: 8)
        let result = range.expanded(to: outer, direction: .downstream)
        XCTAssertEqual(result, NSRange(location: 5, length: 5))
    }

    func testExpandZeroLengthRangeUpstream() {
        let range = NSRange(location: 5, length: 0)
        let outer = NSRange(location: 2, length: 8)
        let result = range.expanded(to: outer, direction: .upstream)
        XCTAssertEqual(result, NSRange(location: 2, length: 3))
    }

    func testExpandZeroLengthRangeDownstream() {
        let range = NSRange(location: 5, length: 0)
        let outer = NSRange(location: 2, length: 8)
        let result = range.expanded(to: outer, direction: .downstream)
        XCTAssertEqual(result, NSRange(location: 5, length: 5))
    }

    func testExpandWhenSelfEqualsOtherReturnsSameRange() {
        let range = NSRange(location: 3, length: 4)
        XCTAssertEqual(range.expanded(to: range, direction: .upstream), range)
        XCTAssertEqual(range.expanded(to: range, direction: .downstream), range)
    }

    func testExpandAtBoundaryStartUpstream() {
        let range = NSRange(location: 2, length: 3)
        let outer = NSRange(location: 2, length: 8)
        let result = range.expanded(to: outer, direction: .upstream)
        XCTAssertEqual(result, NSRange(location: 2, length: 3))
    }

    func testExpandAtBoundaryEndDownstream() {
        let range = NSRange(location: 5, length: 5)
        let outer = NSRange(location: 2, length: 8)
        let result = range.expanded(to: outer, direction: .downstream)
        XCTAssertEqual(result, NSRange(location: 5, length: 5))
    }
}
