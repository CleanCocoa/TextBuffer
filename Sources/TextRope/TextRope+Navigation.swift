extension TextRope {
    internal struct LeafPosition {
        var node: Node
        var offsetInLeaf: Int
    }

    /// - Invariant: `utf16Offset` must be in `0...utf16Count`.
    internal func findLeaf(utf16Offset: Int) -> LeafPosition {
        precondition(utf16Offset >= 0 && utf16Offset <= utf16Count, "findLeaf offset \(utf16Offset) out of range 0...\(utf16Count)")
        var remaining = utf16Offset
        var current = root

        while !current.isLeaf {
            for (index, child) in current.children.enumerated() {
                if remaining < child.summary.utf16 || index == current.children.count - 1 {
                    current = child
                    break
                }
                remaining -= child.summary.utf16
            }
        }

        return LeafPosition(node: current, offsetInLeaf: remaining)
    }

    /// Returns the substring for a half-open range of UTF-16 code unit offsets.
    ///
    /// - Invariant: `utf16Range` must be within `0...utf16Count`.
    public func content(in utf16Range: Range<Int>) -> String {
        precondition(utf16Range.lowerBound >= 0, "content range location \(utf16Range.lowerBound) must be non-negative")
        precondition(utf16Range.upperBound <= utf16Count, "content range end \(utf16Range.upperBound) exceeds utf16Count \(utf16Count)")
        if utf16Range.isEmpty { return "" }

        let startOffset = utf16Range.lowerBound
        let endOffset = utf16Range.upperBound
        var result = ""
        var utf16Pos = 0

        func collect(_ node: Node) {
            if utf16Pos >= endOffset { return }
            let nodeEnd = utf16Pos + node.summary.utf16
            if nodeEnd <= startOffset {
                utf16Pos = nodeEnd
                return
            }

            if node.isLeaf {
                let localStart = max(0, startOffset - utf16Pos)
                let localEnd = min(node.summary.utf16, endOffset - utf16Pos)

                let utf16View = node.chunk.utf16
                let startIdx = utf16View.index(utf16View.startIndex, offsetBy: localStart)
                let endIdx = utf16View.index(utf16View.startIndex, offsetBy: localEnd)
                result += String(node.chunk[startIdx..<endIdx])

                utf16Pos = nodeEnd
            } else {
                for child in node.children {
                    if utf16Pos >= endOffset { break }
                    collect(child)
                }
            }
        }

        collect(root)
        return result
    }

    /// Returns the UTF-16 code units of the rope's content within a half-open offset
    /// range, equal to the corresponding slice of `content`'s `utf16` view.
    ///
    /// Unlike `content(in:)`, the bounds carry no character- or scalar-alignment
    /// requirement: a range that begins or ends between the halves of a surrogate
    /// pair returns the raw unpaired code units. O(log n + k).
    ///
    /// Package-scoped by design: this exists for the TextBuffer target's
    /// composed-sequence machinery and is not part of the library's semver surface.
    ///
    /// - Invariant: `utf16Range` must be within `0...utf16Count`.
    package func utf16CodeUnits(in utf16Range: Range<Int>) -> [UTF16.CodeUnit] {
        precondition(utf16Range.lowerBound >= 0, "utf16CodeUnits range location \(utf16Range.lowerBound) must be non-negative")
        precondition(utf16Range.upperBound <= utf16Count, "utf16CodeUnits range end \(utf16Range.upperBound) exceeds utf16Count \(utf16Count)")
        if utf16Range.isEmpty { return [] }

        let startOffset = utf16Range.lowerBound
        let endOffset = utf16Range.upperBound
        var result: [UTF16.CodeUnit] = []
        result.reserveCapacity(utf16Range.count)
        var utf16Pos = 0

        func collect(_ node: Node) {
            if utf16Pos >= endOffset { return }
            let nodeEnd = utf16Pos + node.summary.utf16
            if nodeEnd <= startOffset {
                utf16Pos = nodeEnd
                return
            }

            if node.isLeaf {
                let localStart = max(0, startOffset - utf16Pos)
                let localEnd = min(node.summary.utf16, endOffset - utf16Pos)

                let utf16View = node.chunk.utf16
                let startIdx = utf16View.index(utf16View.startIndex, offsetBy: localStart)
                let endIdx = utf16View.index(utf16View.startIndex, offsetBy: localEnd)
                result.append(contentsOf: utf16View[startIdx..<endIdx])

                utf16Pos = nodeEnd
            } else {
                for child in node.children {
                    if utf16Pos >= endOffset { break }
                    collect(child)
                }
            }
        }

        collect(root)
        return result
    }
}
