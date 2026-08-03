import Foundation

extension TextRope {
    /// UAX #29 GB12/GB13 regional indicator scalars, `U+1F1E6...U+1F1FF`.
    private static let regionalIndicatorScalars: ClosedRange<UInt32> = 0x1F1E6...0x1F1FF

    /// Maximum backward-walk distance, in UTF-16 units (2,048 regional indicators), when
    /// snapping a window start to the start of its regional indicator run (DEF-002). A run
    /// that continues past the cap falls back silently to full-document expansion — no
    /// assertion in any build configuration — so correctness never depends on the cap; it
    /// only chooses where the cost cliff sits. Deliberately *not* derived from
    /// `Node.maxChunkUTF8`: the cap bounds regional-indicator-run walking, a property of
    /// the text, not of chunk geometry (resolved 2026-08-01).
    private static let regionalIndicatorWalkCap = 4096

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

            let window = content(in: NSRange(location: windowStart, length: windowEnd - windowStart)) as NSString
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
    /// regional indicator — one leaf descent answers both questions, keeping the descent
    /// count of the non-regional-indicator read path unchanged.
    private func scalarAlignedStart(at utf16Offset: Int) -> (offset: Int, isRegionalIndicator: Bool) {
        guard utf16Offset > 0 && utf16Offset < utf16Count else { return (utf16Offset, false) }
        let position = findLeaf(utf16Offset: utf16Offset)
        let chunk = position.node.chunk
        let utf16View = chunk.utf16
        var offset = utf16Offset
        var index = utf16View.index(utf16View.startIndex, offsetBy: position.offsetInLeaf)
        if UTF16.isTrailSurrogate(utf16View[index]) {
            // The lead surrogate is in the same leaf: a chunk seam never splits a scalar (ADR-012).
            offset -= 1
            index = utf16View.index(before: index)
        }
        guard let scalarIndex = index.samePosition(in: chunk.unicodeScalars) else { return (offset, false) }
        return (offset, Self.regionalIndicatorScalars.contains(chunk.unicodeScalars[scalarIndex].value))
    }

    /// The document offset of the first regional indicator in the contiguous run whose
    /// member starts at `utf16Offset`, or `nil` when the walk exceeds `cap` UTF-16 units.
    /// Scans backward within each leaf's chunk and re-descends only at leaf boundaries,
    /// never per code unit.
    ///
    /// - Invariant: `utf16Offset` must be a scalar boundary.
    private func regionalIndicatorRunStart(before utf16Offset: Int, cappedAt cap: Int) -> Int? {
        var runStart = utf16Offset
        while runStart > 0 {
            let position = findLeaf(utf16Offset: runStart - 1)
            let chunk = position.node.chunk
            let scalars = chunk.unicodeScalars
            let utf16View = chunk.utf16
            // `runStart` is a scalar boundary, and a chunk seam never splits a scalar
            // (ADR-012), so the exclusive end converts cleanly into the scalar view.
            let end = utf16View.index(utf16View.startIndex, offsetBy: position.offsetInLeaf + 1)
            var scalarIndex = end.samePosition(in: scalars)!
            while scalarIndex > scalars.startIndex {
                let previous = scalars.index(before: scalarIndex)
                guard Self.regionalIndicatorScalars.contains(scalars[previous].value) else { return runStart }
                runStart -= UTF16.width(scalars[previous])
                if utf16Offset - runStart > cap { return nil }
                scalarIndex = previous
            }
        }
        return 0
    }

    private func isTrailSurrogate(at utf16Offset: Int) -> Bool {
        guard utf16Offset > 0 && utf16Offset < utf16Count else { return false }
        let position = findLeaf(utf16Offset: utf16Offset)
        let utf16View = position.node.chunk.utf16
        let index = utf16View.index(utf16View.startIndex, offsetBy: position.offsetInLeaf)
        return UTF16.isTrailSurrogate(utf16View[index])
    }
}
