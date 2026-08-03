extension TextRope {
    /// Replaces the content within a half-open range of UTF-16 code unit offsets
    /// with the given string, composing `delete(in:)` and `insert(_:at:)`.
    ///
    /// - Invariant: `utf16Range` must be within `0...utf16Count`.
    public mutating func replace(range utf16Range: Range<Int>, with string: String) {
        precondition(utf16Range.lowerBound >= 0, "replace range location \(utf16Range.lowerBound) must be non-negative")
        precondition(utf16Range.upperBound <= utf16Count, "replace range end \(utf16Range.upperBound) exceeds utf16Count \(utf16Count)")
        delete(in: utf16Range)
        insert(string, at: utf16Range.lowerBound)
    }
}
