public protocol TextBuffer<Range> {
    associatedtype Range: BufferRange
    typealias Location = Range.Position
    associatedtype Content: BufferContent<Range.Position>

    var content: Content { get }
    var range: Range { get }
    var selectedRange: Range { get set }
    var insertionLocation: Location { get set }
    var isSelectingText: Bool { get }

    mutating func select(_ range: Range)
    func character(at location: Location) throws(BufferAccessFailure) -> Content
    func content(in subrange: Range) throws(BufferAccessFailure) -> Content
    func unsafeCharacter(at location: Location) -> Content
    mutating func insert(_ content: Content, at location: Location) throws(BufferAccessFailure)
    mutating func insert(_ content: Content) throws(BufferAccessFailure)
    mutating func delete(in deletedRange: Range) throws(BufferAccessFailure)
    mutating func replace(range replacementRange: Range, with content: Content) throws(BufferAccessFailure)
    mutating func modifying<T>(affectedRange: Range, _ block: () -> T) throws(BufferAccessFailure) -> T
}

import Foundation

extension TextBuffer {
    @inlinable @inline(__always)
    public var isSelectingText: Bool { selectedRange.length > 0 }

    @inlinable @inline(__always)
    public var insertionLocation: Location {
        get { selectedRange.location }
        set { selectedRange = Range(location: newValue, length: 0) }
    }

    @inlinable @inline(__always)
    public mutating func select(_ range: Range) {
        selectedRange = range
    }

    @inlinable @inline(__always)
    public mutating func insert(_ content: Content) throws(BufferAccessFailure) {
        try replace(range: selectedRange, with: content)
    }

    @inlinable @inline(__always)
    public func character(at location: Location) throws(BufferAccessFailure) -> Content {
        return try self.content(in: .init(location: location, length: 1))
    }
}
