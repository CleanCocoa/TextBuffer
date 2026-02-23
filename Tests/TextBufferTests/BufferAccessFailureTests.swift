//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

final class BufferAccessFailureTests: XCTestCase {

    // MARK: - outOfRange(requested:available:)

    func testOutOfRange_WithNSRange() {
        let error = BufferAccessFailure.outOfRange(
            requested: NSRange(location: 5, length: 3),
            available: NSRange(location: 0, length: 10)
        )
        XCTAssertEqual(
            error.debugDescription,
            "out of range\ntried to access (5..<8) in available range (0..<10)"
        )
    }

    func testOutOfRange_WithTestRange() {
        let error = BufferAccessFailure.outOfRange(
            requested: TestRange(location: 5, length: 3),
            available: TestRange(location: 0, length: 10)
        )
        XCTAssertEqual(
            error.debugDescription,
            "out of range\ntried to access (5..<8) in available range (0..<10)"
        )
    }

    // MARK: - outOfRange(location:length:available:)

    func testOutOfRange_LocationOverload_MatchesRequestedOverload() {
        let fromLocation = BufferAccessFailure.outOfRange(
            location: 5,
            length: 3,
            available: NSRange(location: 0, length: 10)
        )
        let fromRequested = BufferAccessFailure.outOfRange(
            requested: NSRange(location: 5, length: 3),
            available: NSRange(location: 0, length: 10)
        )
        XCTAssertEqual(fromLocation.debugDescription, fromRequested.debugDescription)
    }

    func testOutOfRange_LocationOverload_WithTestRange() {
        let error = BufferAccessFailure.outOfRange(
            location: 5,
            length: 3,
            available: TestRange(location: 0, length: 10)
        )
        XCTAssertEqual(
            error.debugDescription,
            "out of range\ntried to access (5..<8) in available range (0..<10)"
        )
    }

    func testOutOfRange_LocationOverload_DefaultLengthIsZero() {
        let error: BufferAccessFailure = .outOfRange(
            location: 3,
            available: NSRange(location: 0, length: 2)
        )
        XCTAssertEqual(
            error.debugDescription,
            "out of range\ntried to access (3..<3) in available range (0..<2)"
        )
    }

    // MARK: - modificationForbidden(in:)

    func testModificationForbidden_WithNSRange() {
        let error = BufferAccessFailure.modificationForbidden(
            in: NSRange(location: 5, length: 3)
        )
        XCTAssertEqual(
            error.debugDescription,
            "modification not allowed\ntried to modify (5..<8)"
        )
    }

    func testModificationForbidden_WithTestRange() {
        let error = BufferAccessFailure.modificationForbidden(
            in: TestRange(location: 5, length: 3)
        )
        XCTAssertEqual(
            error.debugDescription,
            "modification not allowed\ntried to modify (5..<8)"
        )
    }

    // MARK: - wrap(_:)

    func testWrap_PassesThroughExistingBufferAccessFailure() {
        let original = BufferAccessFailure.outOfRange(
            requested: NSRange(location: 1, length: 2),
            available: NSRange(location: 0, length: 5)
        )
        let wrapped = BufferAccessFailure.wrap(original)
        XCTAssertEqual(wrapped.debugDescription, original.debugDescription)
    }

    func testWrap_ForeignError() {
        let nsError = NSError(domain: "TestDomain", code: 42, userInfo: [
            NSLocalizedDescriptionKey: "something went wrong"
        ])
        let wrapped = BufferAccessFailure.wrap(nsError)
        XCTAssertEqual(wrapped.label, "")
        XCTAssertEqual(wrapped.context, nsError.localizedDescription)
        XCTAssertNotNil(wrapped.underlyingError)
    }
}
