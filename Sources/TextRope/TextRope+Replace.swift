import Foundation

extension TextRope {
    /// - Invariant: `utf16Range` must be within `0...utf16Count` and `length >= 0`.
    public mutating func replace(range utf16Range: NSRange, with string: String) {
        precondition(utf16Range.location >= 0, "replace range location \(utf16Range.location) must be non-negative")
        precondition(utf16Range.length >= 0, "replace range length \(utf16Range.length) must be non-negative")
        precondition(utf16Range.location + utf16Range.length <= utf16Count, "replace range end \(utf16Range.location + utf16Range.length) exceeds utf16Count \(utf16Count)")
        delete(in: utf16Range)
        insert(string, at: utf16Range.location)
    }
}
