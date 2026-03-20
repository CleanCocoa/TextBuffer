//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

/// Synchronous refinement of ``AsyncBuffer``, the primary protocol for text buffer operations.
///
/// Concrete conformers include ``MutableStringBuffer`` (in-memory) and ``NSTextViewBuffer`` (AppKit-backed).
/// The primary associated type `Range` determines the range representation; `Location` is derived as `Range.Position`.
public protocol Buffer<Range>: AsyncBuffer, TextBuffer {
    var content: Content { get }
    var range: Range { get }
    var selectedRange: Range { get set }
    var insertionLocation: Location { get set }
    var isSelectingText: Bool { get }

    func select(_ range: Range)
    func character(at location: Location) throws(BufferAccessFailure) -> Content
    func content(in subrange: Range) throws(BufferAccessFailure) -> Content
    func unsafeCharacter(at location: Location) -> Content
    func insert(_ content: Content, at location: Location) throws(BufferAccessFailure)
    func insert(_ content: Content) throws(BufferAccessFailure)
    func delete(in deletedRange: Range) throws(BufferAccessFailure)
    func replace(range replacementRange: Range, with content: Content) throws(BufferAccessFailure)
    func modifying<T>(affectedRange: Range, _ block: () -> T) throws(BufferAccessFailure) -> T
}

import Foundation

extension Buffer {
    @inlinable @inline(__always)
    public var isSelectingText: Bool { selectedRange.length > 0 }

    @inlinable @inline(__always)
    public var insertionLocation: Location {
        get { selectedRange.location }
        set { selectedRange = Range(location: newValue, length: 0) }
    }

    @inlinable @inline(__always)
    public func select(_ range: Range) {
        selectedRange = range
    }

    @inlinable @inline(__always)
    public func insert(_ content: Content) throws(BufferAccessFailure) {
        try replace(range: selectedRange, with: content)
    }

    @inlinable @inline(__always)
    public func character(at location: Location) throws(BufferAccessFailure) -> Content {
        return try content(in: .init(location: location, length: 1))
    }

    @inlinable @inline(__always)
    public func getContent() -> Content { content }

    @inlinable @inline(__always)
    public func getRange() -> Range { range }

    @inlinable @inline(__always)
    public func getSelectedRange() -> Range { selectedRange }

    @inlinable @inline(__always)
    public func setSelectedRange(_ range: Range) { selectedRange = range }

    @inlinable @inline(__always)
    public func getInsertionLocation() -> Location { insertionLocation }

    @inlinable @inline(__always)
    public func setInsertionLocation(_ location: Location) { insertionLocation = location }
}
