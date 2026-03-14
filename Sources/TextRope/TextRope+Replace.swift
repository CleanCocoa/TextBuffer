import Foundation

extension TextRope {
    public mutating func replace(range utf16Range: NSRange, with string: String) {
        delete(in: utf16Range)
        insert(string, at: utf16Range.location)
    }
}
