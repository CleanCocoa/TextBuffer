//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

final class BufferRangeDefaultTests: XCTestCase {

    // MARK: - shifted(by:) defaults

    func testShiftedByZero_IsIdentity() {
        let range = TestRange(location: 10, length: 5)
        XCTAssertEqual(range.shifted(by: 0), range)
    }

    func testShiftedBy_PositiveDelta() {
        XCTAssertEqual(
            TestRange(location: 10, length: 5).shifted(by: 3),
            TestRange(location: 13, length: 5)
        )
    }

    func testShiftedBy_NegativeDelta_KeepingLocationPositive() {
        XCTAssertEqual(
            TestRange(location: 10, length: 5).shifted(by: -3),
            TestRange(location: 7, length: 5)
        )
    }

    func testShiftedBy_NegativeDelta_ToExactlyZero() {
        XCTAssertEqual(
            TestRange(location: 10, length: 5).shifted(by: -10),
            TestRange(location: 0, length: 5)
        )
    }

    func testShiftedBy_NegativeDelta_PastZero_PreservesLength() {
        let result = TestRange(location: 100, length: 100).shifted(by: -130)
        XCTAssertEqual(result, TestRange(location: -30, length: 100))
    }

    func testShiftedBy_ZeroLengthRange() {
        XCTAssertEqual(
            TestRange(location: 5, length: 0).shifted(by: 7),
            TestRange(location: 12, length: 0)
        )
    }

    // MARK: - contains(_:) defaults

    func testContains_Self() {
        let range = TestRange(location: 10, length: 5)
        XCTAssertTrue(range.contains(range))
    }

    func testContains_StrictSubset() {
        let outer = TestRange(location: 10, length: 10)
        let inner = TestRange(location: 12, length: 3)
        XCTAssertTrue(outer.contains(inner))
    }

    func testContains_EmptyRangeAtInteriorPosition() {
        let outer = TestRange(location: 10, length: 10)
        XCTAssertTrue(outer.contains(TestRange(location: 15, length: 0)))
    }

    func testContains_EmptyRangeAtEndPosition() {
        let outer = TestRange(location: 10, length: 10)
        XCTAssertTrue(outer.contains(TestRange(location: 20, length: 0)))
    }

    func testDoesNotContain_EmptyRangePastEnd() {
        let outer = TestRange(location: 10, length: 10)
        XCTAssertFalse(outer.contains(TestRange(location: 21, length: 0)))
    }

    func testDoesNotContain_OverlappingRangeStartingBefore() {
        let range = TestRange(location: 10, length: 10)
        let other = TestRange(location: 8, length: 5)
        XCTAssertFalse(range.contains(other))
    }

    func testContains_EmptyContainsEmptyAtSameLocation() {
        let empty = TestRange(location: 5, length: 0)
        XCTAssertTrue(empty.contains(TestRange(location: 5, length: 0)))
    }

    func testContains_EmptyDoesNotContainNonEmpty() {
        let empty = TestRange(location: 5, length: 0)
        XCTAssertFalse(empty.contains(TestRange(location: 5, length: 1)))
    }

    func testContains_ZeroLengthRangesAtDifferentLocations() {
        let a = TestRange(location: 5, length: 0)
        let b = TestRange(location: 6, length: 0)
        XCTAssertFalse(a.contains(b))
    }

    // MARK: - Witness dispatch

    func shiftViaProtocol<R: BufferRange>(_ r: R, by delta: R.Position) -> R {
        r.shifted(by: delta)
    }

    func containsViaProtocol<R: BufferRange>(_ r: R, _ other: R) -> Bool {
        r.contains(other)
    }

    func testNSRange_ShiftedWitness_UsesClampingOverride() {
        let result = shiftViaProtocol(NSRange(location: 100, length: 100), by: -130)
        XCTAssertEqual(result, NSRange(location: 0, length: 70))
    }

    func testNSRange_ContainsWitness_UsesHasValidValuesGuard() {
        let range = NSRange(location: 0, length: 100)
        let negativeLocation = NSRange(location: -1, length: 1)
        XCTAssertFalse(containsViaProtocol(range, negativeLocation))
    }

    // MARK: - Divergence documentation

    func testShifted_DivergenceBetweenNSRangeAndTestRange() {
        let nsResult = NSRange(location: 100, length: 100).shifted(by: -130)
        let testResult = TestRange(location: 100, length: 100).shifted(by: -130)

        XCTAssertEqual(nsResult, NSRange(location: 0, length: 70),
                       "NSRange clamps location to 0 and shrinks length")
        XCTAssertEqual(testResult, TestRange(location: -30, length: 100),
                       "Protocol default allows negative location, preserves length")
    }
}
