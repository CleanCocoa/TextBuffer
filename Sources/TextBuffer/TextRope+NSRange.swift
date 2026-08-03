import Foundation
import TextRope

/// `NSRange` conveniences for `TextRope`, provided by the TextBuffer target.
///
/// The TextRope target is Foundation-free: its primitives take half-open `Range<Int>`
/// values over UTF-16 code unit offsets. These wrappers restate the primitives in
/// `NSRange` terms for Foundation- and AppKit-facing callers. Each validates the
/// degenerate encodings only `NSRange` can represent (`NSNotFound`, negative location
/// or length) and forwards `location ..< location + length` to the primitive, which
/// owns the bounds checks against `utf16Count`.
extension TextRope {
    /// Returns the substring for `utf16Range`, an `NSRange` of UTF-16 code unit offsets.
    ///
    /// - Invariant: `utf16Range` must be within `0...utf16Count` and `length >= 0`.
    @inlinable @inline(__always)
    public func content(in utf16Range: NSRange) -> String {
        precondition(utf16Range.location != NSNotFound, "content range location must not be NSNotFound")
        precondition(utf16Range.location >= 0, "content range location \(utf16Range.location) must be non-negative")
        precondition(utf16Range.length >= 0, "content range length \(utf16Range.length) must be non-negative")
        return content(in: utf16Range.location ..< utf16Range.location + utf16Range.length)
    }

    /// Removes the content within `utf16Range`, an `NSRange` of UTF-16 code unit offsets.
    ///
    /// - Invariant: `utf16Range` must be within `0..<utf16Count` and `length >= 0`.
    @inlinable @inline(__always)
    public mutating func delete(in utf16Range: NSRange) {
        precondition(utf16Range.location != NSNotFound, "delete range location must not be NSNotFound")
        precondition(utf16Range.location >= 0, "delete range location \(utf16Range.location) must be non-negative")
        precondition(utf16Range.length >= 0, "delete range length \(utf16Range.length) must be non-negative")
        delete(in: utf16Range.location ..< utf16Range.location + utf16Range.length)
    }

    /// Replaces the content within `utf16Range`, an `NSRange` of UTF-16 code unit
    /// offsets, with `string`.
    ///
    /// - Invariant: `utf16Range` must be within `0...utf16Count` and `length >= 0`.
    @inlinable @inline(__always)
    public mutating func replace(range utf16Range: NSRange, with string: String) {
        precondition(utf16Range.location != NSNotFound, "replace range location must not be NSNotFound")
        precondition(utf16Range.location >= 0, "replace range location \(utf16Range.location) must be non-negative")
        precondition(utf16Range.length >= 0, "replace range length \(utf16Range.length) must be non-negative")
        replace(range: utf16Range.location ..< utf16Range.location + utf16Range.length, with: string)
    }
}
