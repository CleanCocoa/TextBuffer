//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation

/// An abstraction over range types (such as `NSRange`) for use with ``Buffer`` and ``AsyncBuffer``.
///
/// Conforming types represent a contiguous range within a buffer, parameterized by a `Position` type
/// that determines how locations are expressed (e.g., `Int` for UTF-16 offsets).
public protocol BufferRange<Position> {
    /// The index type used to express positions within a buffer (e.g., `Int` for UTF-16 offsets, `String.Index` for native Swift string indexing).
    associatedtype Position: Comparable & AdditiveArithmetic & ExpressibleByIntegerLiteral

    /// The start position of the range.
    var location: Position { get }

    /// The number of elements covered by the range.
    var length: Position { get }

    /// Creates a range starting at `location` with the given `length`.
    init(location: Position, length: Position)

    /// Returns `true` if this range fully contains `other`.
    func contains(_ other: Self) -> Bool

    /// Returns a copy of this range shifted by `delta` positions.
    func shifted(by delta: Position) -> Self

    /// Returns the portion of this range that remains after removing the overlap with `other`.
    func subtracting(_ other: Self) -> Self

    /// Removes the overlap with `other` from this range in place.
    mutating func subtract(_ other: Self)
}

extension BufferRange {
    @inlinable @inline(__always)
    public func shifted(by delta: Position) -> Self {
        Self(location: location + delta, length: length)
    }

    @inlinable @inline(__always)
    public func contains(_ other: Self) -> Bool {
        location <= other.location
            && (location + length) >= (other.location + other.length)
    }
}

/// `NSRange` conformance to ``BufferRange``.
///
/// All requirements are satisfied by Foundation and existing `NSRange` extensions in this package.
extension NSRange: BufferRange {
    public typealias Position = Int
}
