import Foundation

extension TextRope {
    /// Content of `utf16Range` expanded to composed character sequence boundaries,
    /// matching `NSString.rangeOfComposedCharacterSequences(for:)`.
    ///
    /// - Invariant: `utf16Range` must be within `0...utf16Count` and `length >= 0`.
    public func composedCharacterSequences(in utf16Range: NSRange) -> String {
        if utf16Range.length == 0 { return "" }
        precondition(utf16Range.location >= 0, "composed sequences range location \(utf16Range.location) must be non-negative")
        precondition(utf16Range.length >= 0, "composed sequences range length \(utf16Range.length) must be non-negative")
        precondition(utf16Range.location + utf16Range.length <= utf16Count, "composed sequences range end \(utf16Range.location + utf16Range.length) exceeds utf16Count \(utf16Count)")
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
    private func expandingWindow(around utf16Range: NSRange, _ expand: (NSString, NSRange) -> NSRange) -> String {
        var radius = 128
        while true {
            var windowStart = max(0, utf16Range.location - radius)
            var windowEnd = min(utf16Count, utf16Range.location + utf16Range.length + radius)
            if isTrailSurrogate(at: windowStart) { windowStart -= 1 }
            if isTrailSurrogate(at: windowEnd) { windowEnd += 1 }

            let window = content(in: NSRange(location: windowStart, length: windowEnd - windowStart)) as NSString
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

    private func isTrailSurrogate(at utf16Offset: Int) -> Bool {
        guard utf16Offset > 0 && utf16Offset < utf16Count else { return false }
        let position = findLeaf(utf16Offset: utf16Offset)
        let utf16View = position.node.chunk.utf16
        let index = utf16View.index(utf16View.startIndex, offsetBy: position.offsetInLeaf)
        return UTF16.isTrailSurrogate(utf16View[index])
    }
}
