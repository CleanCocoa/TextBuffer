import Foundation
import TextRope

public final class RopeBuffer: Buffer, TextAnalysisCapable {
    public typealias Range = NSRange
    public typealias Content = String

    @usableFromInline
    internal var rope: TextRope

    public var selectedRange: NSRange

    public init(_ content: String = "") {
        self.rope = TextRope(content)
        self.selectedRange = NSRange(location: 0, length: 0)
    }

    @inlinable
    public var range: NSRange { NSRange(location: 0, length: rope.utf16Count) }

    @inlinable
    public var content: String { rope.content }

    @inlinable
    public func lineRange(for searchRange: NSRange) throws(BufferAccessFailure) -> NSRange {
        guard contains(range: searchRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: searchRange,
                available: self.range
            )
        }
        return (self.content as NSString).lineRange(for: searchRange)
    }

    @inlinable
    public func content(in subrange: NSRange) throws(BufferAccessFailure) -> String {
        guard contains(range: subrange) else {
            throw BufferAccessFailure.outOfRange(
                requested: subrange,
                available: self.range
            )
        }
        return rope.content(in: subrange)
    }

    @inlinable
    public func unsafeCharacter(at location: Int) -> String {
        return rope.content(in: NSRange(location: location, length: 1))
    }

    @inlinable
    public func insert(_ content: String, at location: Int) throws(BufferAccessFailure) {
        guard contains(range: NSRange(location: location, length: 0)) else {
            throw BufferAccessFailure.outOfRange(
                location: location,
                available: self.range
            )
        }

        rope.insert(content, at: location)

        self.selectedRange = self.selectedRange
            .shifted(by: location <= self.selectedRange.location ? content.utf16.count : 0)
    }

    @inlinable
    public func delete(in deletedRange: NSRange) throws(BufferAccessFailure) {
        guard contains(range: deletedRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: deletedRange,
                available: self.range
            )
        }

        rope.delete(in: deletedRange)
        self.selectedRange.subtract(deletedRange)
    }

    @inlinable
    public func replace(range replacementRange: NSRange, with content: String) throws(BufferAccessFailure) {
        guard contains(range: replacementRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: replacementRange,
                available: self.range
            )
        }

        rope.replace(range: replacementRange, with: content)

        self.selectedRange = self.selectedRange
            .subtracting(replacementRange)
            .shifted(by: replacementRange.location <= self.selectedRange.location ? content.utf16.count : 0)
    }

    @inlinable
    public func modifying<T>(affectedRange: NSRange, _ block: () -> T) throws(BufferAccessFailure) -> T {
        guard contains(range: affectedRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: affectedRange,
                available: self.range
            )
        }

        return block()
    }

    @inlinable
    public func setInsertionLocation(_ location: Int) {
        selectedRange = NSRange(location: location, length: 0)
    }
}

extension RopeBuffer {
    public convenience init<Wrapped>(
        copying buffer: Wrapped
    ) where Wrapped: Buffer, Wrapped.Range == NSRange, Wrapped.Content == String {
        self.init(buffer.content)
        self.selectedRange = buffer.selectedRange
    }
}

extension RopeBuffer: Equatable {
    public static func == (lhs: RopeBuffer, rhs: RopeBuffer) -> Bool {
        return lhs.selectedRange == rhs.selectedRange
            && lhs.rope == rhs.rope
    }
}

@available(*, unavailable)
extension RopeBuffer: @unchecked Sendable {}
