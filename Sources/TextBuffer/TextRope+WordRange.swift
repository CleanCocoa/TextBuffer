import Foundation
import TextRope

extension TextRope {
    /// Initial window radius, in UTF-16 units, around the search range for the windowed
    /// word expansion (mirrors `expandingWindow`'s radius in `TextRope+ComposedSequences.swift`).
    private static let wordWindowInitialRadius = 128

    /// The word range around `searchRange`, matching the full-document
    /// `computeWordRange(for:in:contentRange:)` answer (the `TextAnalysisCapable`
    /// default / `MutableStringBuffer` behavior) — without materializing the full
    /// document: `computeWordRange` runs verbatim over a materialized window, and the
    /// window doubles whenever the answer could have been shaped by a window edge.
    /// O(log n + word length); an all-whitespace document degenerately doubles out to
    /// the full document, which is then the exact full-document call.
    ///
    /// Retry conditions (design D4 of `rope-log-queries`), each requiring document
    /// beyond the edge in question:
    /// - the result touches a window edge — a word run may continue past it;
    /// - the whitespace scan was inconclusive: every unit between the search range and a
    ///   window edge is whitespace, so a scan in that direction ran off the window
    ///   without resolving. An all-whitespace stretch says nothing about what lies just
    ///   beyond it — `computeWordRange`'s window-relative fallbacks ("no boundary found"
    ///   means "ran off the window") must not be mistaken for answers. This deliberately
    ///   errs conservative: it also widens when the other direction already found a
    ///   word, because full-document semantics may prefer a closer word beyond the edge.
    ///
    /// - Invariant: `searchRange` must be within `0...utf16Count` (the buffers guard
    ///   bounds and throw before calling).
    internal func wordRange(for searchRange: NSRange) -> NSRange {
        var radius = Self.wordWindowInitialRadius
        while true {
            var windowStart = Swift.max(0, searchRange.location - radius)
            var windowEnd = Swift.min(utf16Count, searchRange.location + searchRange.length + radius)
            // Align window edges to scalar boundaries: an edge may land on a trail
            // surrogate. No regional-indicator run anchoring is needed — `CharacterSet`
            // classification is per-scalar, so window placement cannot flip it.
            if isTrailSurrogate(atOffset: windowStart) { windowStart -= 1 }
            if isTrailSurrogate(atOffset: windowEnd) { windowEnd += 1 }

            let window = content(in: windowStart ..< windowEnd) as NSString
            let local = NSRange(location: searchRange.location - windowStart, length: searchRange.length)
            let localResult = computeWordRange(
                for: local,
                in: window,
                contentRange: NSRange(location: 0, length: window.length)
            )

            let documentContinuesBeforeWindow = windowStart > 0
            let documentContinuesAfterWindow = windowEnd < utf16Count

            let touchesLeadingEdge = documentContinuesBeforeWindow
                && localResult.location == 0
            let touchesTrailingEdge = documentContinuesAfterWindow
                && localResult.location + localResult.length == window.length
            let leadingWhitespaceScanInconclusive = documentContinuesBeforeWindow
                && isAllWhitespace(window, in: NSRange(location: 0, length: local.location))
            let trailingWhitespaceScanInconclusive = documentContinuesAfterWindow
                && isAllWhitespace(window, in: NSRange(
                    location: local.location + local.length,
                    length: window.length - (local.location + local.length)
                ))

            if !touchesLeadingEdge, !touchesTrailingEdge,
               !leadingWhitespaceScanInconclusive, !trailingWhitespaceScanInconclusive {
                return NSRange(location: localResult.location + windowStart, length: localResult.length)
            }
            radius *= 2
        }
    }

    private func isAllWhitespace(_ window: NSString, in range: NSRange) -> Bool {
        if range.length == 0 { return true }
        return window.rangeOfCharacter(from: .nonWhitespaceOrNewlines, options: [], range: range).location == NSNotFound
    }

    private func isTrailSurrogate(atOffset utf16Offset: Int) -> Bool {
        guard utf16Offset > 0 && utf16Offset < utf16Count else { return false }
        return UTF16.isTrailSurrogate(utf16CodeUnits(in: utf16Offset ..< utf16Offset + 1)[0])
    }
}
