import Foundation
import TextRope

extension TextRope {
    /// UAX #29 GB12/GB13 regional indicator scalars, `U+1F1E6...U+1F1FF`.
    private static let regionalIndicatorScalars: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF

    /// Maximum backward-walk distance, in UTF-16 units (2,048 regional indicators), when
    /// snapping a window start to the start of its regional indicator run (DEF-002). A run
    /// that continues past the cap falls back silently to full-document expansion — no
    /// assertion in any build configuration — so correctness never depends on the cap; it
    /// only chooses where the cost cliff sits. Deliberately *not* derived from
    /// chunk geometry: the cap bounds regional-indicator-run walking, a property of
    /// the text, not of the rope's internal layout (resolved 2026-08-01).
    private static let regionalIndicatorWalkCap = 4096

    /// Block size, in UTF-16 units, for the backward reads of the regional indicator run
    /// walk: each `utf16CodeUnits(in:)` call descends the tree once and returns a block
    /// scanned in memory, so the walk costs O(runLength + blocks·log n) instead of one
    /// descent per code unit (the `fix-composed-sequence-reads` D2 mitigation).
    private static let regionalIndicatorWalkBlockSize = 128

    /// Content of `utf16Range` expanded to composed character sequence boundaries,
    /// matching `NSString.rangeOfComposedCharacterSequences(for:)`.
    ///
    /// - Invariant: `utf16Range` must be within `0...utf16Count` and `length >= 0`.
    public func composedCharacterSequences(in utf16Range: NSRange) -> String {
        precondition(utf16Range.location >= 0, "composed sequences range location \(utf16Range.location) must be non-negative")
        precondition(utf16Range.length >= 0, "composed sequences range length \(utf16Range.length) must be non-negative")
        precondition(utf16Range.location + utf16Range.length <= utf16Count, "composed sequences range end \(utf16Range.location + utf16Range.length) exceeds utf16Count \(utf16Count)")
        if utf16Range.length == 0 { return "" }
        return expandingWindow(around: utf16Range) { window, local in
            window.rangeOfComposedCharacterSequences(for: local)
        }
    }

    /// The full composed character sequence containing `utf16Offset`,
    /// matching `NSString.rangeOfComposedCharacterSequence(at:)`.
    ///
    /// - Invariant: `utf16Offset` must be in `0..<utf16Count`.
    public func composedCharacterSequence(at utf16Offset: Int) -> String {
        precondition(utf16Offset >= 0 && utf16Offset < utf16Count, "composed sequence offset \(utf16Offset) out of range 0..<\(utf16Count)")
        return expandingWindow(around: NSRange(location: utf16Offset, length: 1)) { window, local in
            window.rangeOfComposedCharacterSequence(at: local.location)
        }
    }

    /// Materializes only a window around `utf16Range` for the boundary search, doubling the
    /// window whenever the expansion result touches a window edge, so a sequence is never
    /// cut short by the window itself.
    ///
    /// Window invariants:
    /// - The window never starts strictly inside a regional indicator run: its start is
    ///   snapped back to the run start so GB12/GB13 pairing inside the window matches
    ///   full-document pairing (DEF-002; see `scalarAlignedStart(at:)`).
    /// - A run continuing past `regionalIndicatorWalkCap` abandons windowing for this call
    ///   and expands over the full document, silently.
    /// - The materialized window holds exactly the requested UTF-16 units — guaranteed
    ///   structurally by ADR-012's grapheme-first chunk bounds and enforced by a
    ///   precondition (DEF-009).
    private func expandingWindow(around utf16Range: NSRange, _ expand: (NSString, NSRange) -> NSRange) -> String {
        var radius = 128
        while true {
            var windowStart = max(0, utf16Range.location - radius)
            var windowEnd = min(utf16Count, utf16Range.location + utf16Range.length + radius)
            let start = scalarAlignedStart(at: windowStart)
            windowStart = start.offset
            if isTrailSurrogate(at: windowEnd) { windowEnd += 1 }

            // UAX #29 GB12/13 pair regional indicators counting from the start of the
            // maximal RI run — unbounded left context the edge-touch retry below cannot
            // see: a window starting mid-run holds complete but mispaired flags that touch
            // no edge. Anchoring the start at the run start restores document-equal
            // pairing parity (DEF-002).
            if start.isRegionalIndicator, windowStart > 0 {
                guard let runStart = regionalIndicatorRunStart(before: windowStart, cappedAt: Self.regionalIndicatorWalkCap) else {
                    let full = content as NSString
                    return full.substring(with: expand(full, utf16Range))
                }
                windowStart = runStart
            }

            let window = content(in: windowStart ..< windowEnd) as NSString
            precondition(
                window.length == windowEnd - windowStart,
                "DEF-009: materialized window holds \(window.length) UTF-16 units instead of the requested \(windowEnd - windowStart); ADR-012 guarantees no chunk seam falls inside a Character, so the rope's internal invariants are broken"
            )
            let local = NSRange(location: utf16Range.location - windowStart, length: utf16Range.length)
            let expanded = expand(window, local)

            let touchesLeadingEdge = expanded.location == 0 && windowStart > 0
            let touchesTrailingEdge = expanded.location + expanded.length == window.length && windowEnd < utf16Count
            if !touchesLeadingEdge && !touchesTrailingEdge {
                return window.substring(with: expanded)
            }
            radius *= 2
        }
    }

    /// Snaps `utf16Offset` back to the scalar boundary at or before it (a window edge may
    /// land on a trail surrogate) and reports whether the scalar starting there is a
    /// regional indicator — one block read of at most three code units answers both
    /// questions, keeping the read count of the non-regional-indicator path at one.
    private func scalarAlignedStart(at utf16Offset: Int) -> (offset: Int, isRegionalIndicator: Bool) {
        guard utf16Offset > 0 && utf16Offset < utf16Count else { return (utf16Offset, false) }
        // units[0] is the unit before the offset (needed when the offset lands on a trail
        // surrogate), units[1] the unit at the offset, units[2] — when available — the
        // unit after it (needed to decode a lead surrogate at the offset).
        let units = utf16CodeUnits(in: utf16Offset - 1 ..< min(utf16Offset + 2, utf16Count))
        var offset = utf16Offset
        let scalarValue: UInt32
        if UTF16.isTrailSurrogate(units[1]) {
            // The lead surrogate is the previous unit: the rope holds a valid `String`,
            // so surrogate halves always pair.
            offset -= 1
            scalarValue = Self.decodedSurrogatePair(lead: units[0], trail: units[1])
        } else if UTF16.isLeadSurrogate(units[1]), units.count > 2 {
            scalarValue = Self.decodedSurrogatePair(lead: units[1], trail: units[2])
        } else {
            scalarValue = UInt32(units[1])
        }
        return (offset, Self.regionalIndicatorScalars.contains(scalarValue))
    }

    /// The document offset of the first regional indicator in the contiguous run whose
    /// member starts at `utf16Offset`, or `nil` when the walk exceeds `cap` UTF-16 units.
    /// Reads backward in `regionalIndicatorWalkBlockSize`-unit blocks and scans each block
    /// in memory, never descending the tree per code unit.
    ///
    /// - Invariant: `utf16Offset` must be a scalar boundary.
    private func regionalIndicatorRunStart(before utf16Offset: Int, cappedAt cap: Int) -> Int? {
        var runStart = utf16Offset
        while runStart > 0 {
            let blockStart = max(0, runStart - Self.regionalIndicatorWalkBlockSize)
            let units = utf16CodeUnits(in: blockStart ..< runStart)
            var i = units.count
            while i > 0 {
                let unit = units[i - 1]
                let width: Int
                let value: UInt32
                if UTF16.isTrailSurrogate(unit) {
                    // A block edge can split a surrogate pair. `runStart` is a scalar
                    // boundary (the pair ends here), so re-entering the outer loop
                    // fetches a block that contains the lead half.
                    guard i >= 2 else { break }
                    value = Self.decodedSurrogatePair(lead: units[i - 2], trail: unit)
                    width = 2
                } else {
                    value = UInt32(unit)
                    width = 1
                }
                guard Self.regionalIndicatorScalars.contains(value) else { return runStart }
                runStart -= width
                i -= width
                if utf16Offset - runStart > cap { return nil }
            }
        }
        return 0
    }

    private func isTrailSurrogate(at utf16Offset: Int) -> Bool {
        guard utf16Offset > 0 && utf16Offset < utf16Count else { return false }
        return UTF16.isTrailSurrogate(utf16CodeUnits(in: utf16Offset ..< utf16Offset + 1)[0])
    }

    /// The Unicode scalar value encoded by a UTF-16 surrogate pair.
    private static func decodedSurrogatePair(lead: UTF16.CodeUnit, trail: UTF16.CodeUnit) -> UInt32 {
        return 0x10000 + ((UInt32(lead) - 0xD800) << 10) + (UInt32(trail) - 0xDC00)
    }
}
