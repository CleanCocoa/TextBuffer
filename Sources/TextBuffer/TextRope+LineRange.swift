import Foundation
import TextRope

extension TextRope {
    /// Block size, in UTF-16 units, for the line-delimiter scans: each `utf16CodeUnits(in:)`
    /// call descends the tree once and returns a block scanned in memory, so a scan costs
    /// O(lineLength + blocks·log n) instead of one descent per code unit (mirrors
    /// `regionalIndicatorWalkBlockSize` in `TextRope+ComposedSequences.swift`).
    private static let lineWalkBlockSize = 128

    private static let lineFeed: UTF16.CodeUnit = 0x000A
    private static let carriageReturn: UTF16.CodeUnit = 0x000D

    /// Foundation's `NSString.lineRange(for:)` delimiter set: LF, CR, NEL (`U+0085`),
    /// LINE SEPARATOR (`U+2028`), PARAGRAPH SEPARATOR (`U+2029`). CRLF longest-match is
    /// handled at the call sites, not here.
    private static func isLineDelimiter(_ unit: UTF16.CodeUnit) -> Bool {
        switch unit {
        case 0x000A, 0x000D, 0x0085, 0x2028, 0x2029: return true
        default: return false
        }
    }

    /// The range of the line(s) containing `searchRange`, matching
    /// `NSString.lineRange(for:)` over the full document — without materializing it:
    /// a backward block-walk from the range's location finds the nearest delimiter end,
    /// a forward block-walk from the range's end finds the next one. O(log n + line length).
    ///
    /// - Invariant: `searchRange` must be within `0...utf16Count` (the buffers guard
    ///   bounds and throw before calling).
    internal func lineRange(for searchRange: NSRange) -> NSRange {
        let start = lineStart(before: searchRange.location)
        let end = lineEnd(from: searchRange)
        return NSRange(location: start, length: end - start)
    }

    /// The position after the nearest line-delimiter end at or before `location - 1`, or 0.
    private func lineStart(before location: Int) -> Int {
        guard location > 0 else { return 0 }

        var scanUpperBound = location
        // CRLF longest match: a location *between* the `\r` and `\n` of a CRLF pair is
        // inside a single delimiter — NSString treats it as part of the line the CRLF
        // terminates, so the backward scan must skip the `\r` and keep looking. This is
        // the only backward-direction CRLF case: a delimiter found *before* the location
        // ends the previous line at its last unit regardless of a preceding `\r`.
        if location < utf16Count {
            let pair = utf16CodeUnits(in: location - 1 ..< location + 1)
            if pair[0] == Self.carriageReturn && pair[1] == Self.lineFeed {
                scanUpperBound = location - 1
            }
        }

        var upper = scanUpperBound
        while upper > 0 {
            let lower = Swift.max(0, upper - Self.lineWalkBlockSize)
            let units = utf16CodeUnits(in: lower ..< upper)
            var i = units.count - 1
            while i >= 0 {
                if Self.isLineDelimiter(units[i]) { return lower + i + 1 }
                i -= 1
            }
            upper = lower
        }
        return 0
    }

    /// The position after the next line-delimiter end at or after the last unit of
    /// `searchRange` (its location when empty — a range ending just past a delimiter
    /// still belongs to that line per NSString), or `utf16Count`.
    private func lineEnd(from searchRange: NSRange) -> Int {
        let count = utf16Count
        var pos = searchRange.length > 0 ? searchRange.location + searchRange.length - 1 : searchRange.location
        while pos < count {
            let blockEnd = Swift.min(count, pos + Self.lineWalkBlockSize)
            let units = utf16CodeUnits(in: pos ..< blockEnd)
            for (i, unit) in units.enumerated() where Self.isLineDelimiter(unit) {
                let delimiterPosition = pos + i
                // CRLF longest match: a `\r` extends over an immediately following `\n`,
                // peeked across the block boundary when the `\r` is the block's last unit.
                if unit == Self.carriageReturn, delimiterPosition + 1 < count {
                    let next = i + 1 < units.count
                        ? units[i + 1]
                        : utf16CodeUnits(in: delimiterPosition + 1 ..< delimiterPosition + 2)[0]
                    if next == Self.lineFeed { return delimiterPosition + 2 }
                }
                return delimiterPosition + 1
            }
            pos = blockEnd
        }
        return count
    }
}
