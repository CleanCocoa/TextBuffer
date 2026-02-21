//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation

/// Refinement of ``Buffer`` for buffers that support text analysis operations like word and line
/// range expansion.
///
/// Conformers gain default implementations of ``wordRange(for:)`` and ``lineRange(for:)`` when
/// `Range == NSRange` and `Content == String`, backed by Foundation's `NSString` character
/// classification. Buffers with non-String content types (ropes, attributed strings, etc.) can
/// provide their own implementations.
///
/// Concrete conformers: ``MutableStringBuffer``, ``NSTextViewBuffer``, and conditionally
/// ``Undoable`` when its base conforms.
public protocol TextAnalysisCapable: Buffer {
    /// Expanded `searchRange` to cover whole lines. Chained calls return the same line range,
    /// i.e. does not expand line by line.
    ///
    /// Quoting from `Foundation.NSString.lineRange(for:)` (as of 2024-06-04, Xcode 15.4):
    ///
    /// > NSString: A line is delimited by any of these characters, the longest possible sequence
    /// > being preferred to any shorter:
    /// >
    /// > - `U+000A` Unicode Character 'LINE FEED (LF)' (`\n`)
    /// > - `U+000D` Unicode Character 'CARRIAGE RETURN (CR)' (`\r`)
    /// > - `U+0085` Unicode Character 'NEXT LINE (NEL)'
    /// > - `U+2028` Unicode Character 'LINE SEPARATOR'
    /// > - `U+2029` Unicode Character 'PARAGRAPH SEPARATOR'
    /// > - `\r\n`, in that order (also known as `CRLF`)
    ///
    /// - Throws: ``BufferAccessFailure`` if `searchRange` exceeds ``Buffer/range``.
    func lineRange(for searchRange: Range) throws(BufferAccessFailure) -> Range

    /// Expanded `searchRange` to cover whole words. Chained calls return the same word range,
    /// i.e. does not expand word by word.
    ///
    /// - Throws: ``BufferAccessFailure`` if `searchRange` exceeds ``Buffer/range``.
    func wordRange(for searchRange: Range) throws(BufferAccessFailure) -> Range
}

extension TextAnalysisCapable where Range == NSRange, Content == String {
    @inlinable
    public func wordRange(for baseRange: NSRange) throws(BufferAccessFailure) -> NSRange {
        guard contains(range: baseRange)
        else { throw BufferAccessFailure.outOfRange(requested: baseRange, available: self.range) }
        return computeWordRange(for: baseRange, in: (self.content as NSString), contentRange: self.range)
    }

    @inlinable
    public func lineRange(for searchRange: NSRange) throws(BufferAccessFailure) -> NSRange {
        guard contains(range: searchRange)
        else { throw BufferAccessFailure.outOfRange(requested: searchRange, available: self.range) }
        return (self.content as NSString).lineRange(for: searchRange)
    }
}
