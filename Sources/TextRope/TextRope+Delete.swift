import Foundation

extension TextRope {
    /// - Invariant: `utf16Range` must be within `0..<utf16Count` and `length >= 0`.
    public mutating func delete(in utf16Range: NSRange) {
        if utf16Range.length == 0 { return }
        precondition(utf16Range.location >= 0, "delete range location \(utf16Range.location) must be non-negative")
        precondition(utf16Range.length >= 0, "delete range length \(utf16Range.length) must be non-negative")
        precondition(utf16Range.location + utf16Range.length <= utf16Count, "delete range end \(utf16Range.location + utf16Range.length) exceeds utf16Count \(utf16Count)")
        delete(in: utf16Range.location ..< utf16Range.location + utf16Range.length)
    }

    /// Removes the content within a half-open range of UTF-16 code unit offsets.
    ///
    /// - Invariant: `utf16Range` must be within `0..<utf16Count`.
    public mutating func delete(in utf16Range: Range<Int>) {
        if utf16Range.isEmpty { return }
        precondition(utf16Range.lowerBound >= 0, "delete range location \(utf16Range.lowerBound) must be non-negative")
        precondition(utf16Range.upperBound <= utf16Count, "delete range end \(utf16Range.upperBound) exceeds utf16Count \(utf16Count)")
        ensureUnique()

        let start = utf16Range.lowerBound
        let end = utf16Range.upperBound

        _ = Self.deleteFromNode(root, utf16Start: start, utf16End: end)

        while !root.isLeaf && root.children.count == 1 {
            root = root.children[0]
        }

        if root.summary.utf8 == 0 {
            root = Node.emptyLeaf()
        }
    }

    private static func deleteFromNode(_ node: Node, utf16Start: Int, utf16End: Int) -> Bool {
        if node.isLeaf {
            return deleteFromLeaf(node, utf16Start: utf16Start, utf16End: utf16End)
        } else {
            return deleteFromInner(node, utf16Start: utf16Start, utf16End: utf16End)
        }
    }

    private static func deleteFromLeaf(_ node: Node, utf16Start: Int, utf16End: Int) -> Bool {
        let localStart = max(0, utf16Start)
        let localEnd = min(node.summary.utf16, utf16End)

        if localStart >= localEnd { return false }

        let utf16View = node.chunk.utf16
        let startIdx = utf16View.index(utf16View.startIndex, offsetBy: localStart)
        let endIdx = utf16View.index(utf16View.startIndex, offsetBy: localEnd)

        node.chunk.removeSubrange(startIdx..<endIdx)
        node.summary = Summary.of(node.chunk)

        return node.chunk.utf8.count < Node.minChunkUTF8
    }

    private static func deleteFromInner(_ node: Node, utf16Start: Int, utf16End: Int) -> Bool {
        var utf16Pos = 0
        var indicesToRemove: [Int] = []
        var childBecameUndersized = false

        for i in 0..<node.children.count {
            // Read only the scalar, never the node: a `Node` binding here would be a second
            // strong reference still live when `ensureUniqueChild(at:)` runs below, making
            // `isKnownUniquelyReferenced` fail and forcing a path copy on every delete (DEF-003).
            let childUTF16 = node.children[i].summary.utf16
            let childEnd = utf16Pos + childUTF16

            if utf16Pos >= utf16End { break }

            if childEnd <= utf16Start {
                utf16Pos = childEnd
                continue
            }

            let localStart = utf16Start - utf16Pos
            let localEnd = utf16End - utf16Pos

            if localStart <= 0 && localEnd >= childUTF16 {
                indicesToRemove.append(i)
            } else {
                node.ensureUniqueChild(at: i)
                if deleteFromNode(node.children[i], utf16Start: localStart, utf16End: localEnd) {
                    childBecameUndersized = true
                }
            }

            utf16Pos = childEnd
        }

        for i in indicesToRemove.reversed() {
            node.children.remove(at: i)
        }

        if childBecameUndersized || !indicesToRemove.isEmpty || hasCRLFSeam(node) {
            mergeUndersizedChildren(node)
        }
        recalculateSummary(node)

        return node.children.count < Node.minChildren
    }

    private static func hasCRLFSeam(_ node: Node) -> Bool {
        guard node.children.count > 1 else { return false }
        for i in 0..<(node.children.count - 1) {
            if crlfSeam(between: node.children[i], and: node.children[i + 1]) {
                return true
            }
        }
        return false
    }

    static func recalculateSummary(_ node: Node) {
        var summary = Summary.zero
        for child in node.children {
            summary.add(child.summary)
        }
        node.summary = summary
    }
}
