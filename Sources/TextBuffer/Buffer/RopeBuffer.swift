import Foundation
import TextRope

/// A ``Buffer`` implementation backed by a `TextRope` for efficient manipulation of large texts.
///
/// `RopeBuffer` provides O(log n) insert, delete, and replace operations, making it a better choice
/// than ``MutableStringBuffer`` for very large documents. The text-analysis queries
/// ``lineRange(for:)`` and ``wordRange(for:)`` are O(log n + result length) via windowed rope
/// reads — they never materialize the full document, though a delimiter-free document degenerately
/// makes the line (and thus the result) the whole document.
///
/// `RopeBuffer` is a reference type and is **not** `Sendable`. For a thread-safe value-type alternative,
/// use ``SendableRopeBuffer``.
///
/// `RopeBuffer` does not include built-in undo support. Wrap it in ``Undoable`` or ``TransferableUndoable``
/// to add undo/redo.
///
/// To copy another buffer's content, use ``init(copying:)``.
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

    public func lineRange(for searchRange: NSRange) throws(BufferAccessFailure) -> NSRange {
        guard contains(range: searchRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: searchRange,
                available: self.range
            )
        }
        return rope.lineRange(for: searchRange)
    }

    public func wordRange(for searchRange: NSRange) throws(BufferAccessFailure) -> NSRange {
        guard contains(range: searchRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: searchRange,
                available: self.range
            )
        }
        return rope.wordRange(for: searchRange)
    }

    @inlinable
    public func content(in subrange: NSRange) throws(BufferAccessFailure) -> String {
        guard contains(range: subrange) else {
            throw BufferAccessFailure.outOfRange(
                requested: subrange,
                available: self.range
            )
        }
        return rope.composedCharacterSequences(in: subrange)
    }

    @inlinable
    public func unsafeCharacter(at location: Int) -> String {
        return rope.composedCharacterSequence(at: location)
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

        rope.delete(in: deletedRange.location ..< deletedRange.endLocation)
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

        rope.replace(range: replacementRange.location ..< replacementRange.endLocation, with: content)

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
    ) where Wrapped: TextBuffer, Wrapped.Range == NSRange, Wrapped.Content == String {
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

extension RopeBuffer: CustomStringConvertible {
    /// A textual representation of this buffer that includes its selection in the output.
    ///
    /// - Selected ranges will be wrapped in guillemets (`«...»`), while
    /// - insertion point locations will show as `ˇ`.
    public var description: String {
        let result = NSMutableString(string: content)
        if isSelectingText {
            result.insert("»", at: selectedRange.endLocation)
            result.insert("«", at: selectedRange.location)
        } else {
            result.insert("ˇ", at: selectedRange.location)
        }
        return result as String
    }
}

@available(*, unavailable)
extension RopeBuffer: @unchecked Sendable {}
