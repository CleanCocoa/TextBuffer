extension TextRope.Node {
    func splitLeaf() -> TextRope.Node {
        let mid = Self.leafSplitPoint(in: chunk[...])
        let left = String(chunk[chunk.startIndex..<mid])
        let right = String(chunk[mid..<chunk.endIndex])
        chunk = left
        summary = TextRope.Summary.of(left)
        return TextRope.Node.leaf(right)
    }

    func splitInner() -> [TextRope.Node] {
        let total = children.count
        let groupCount = (total + Self.maxChildren - 1) / Self.maxChildren
        let base = total / groupCount
        let extra = total % groupCount

        var siblings: [TextRope.Node] = []
        var start = base + (extra > 0 ? 1 : 0)
        let firstGroupEnd = start
        for group in 1..<groupCount {
            let size = base + (group < extra ? 1 : 0)
            siblings.append(TextRope.Node.inner(ContiguousArray(children[start..<(start + size)])))
            start += size
        }

        children.removeSubrange(firstGroupEnd...)
        var recomputed = TextRope.Summary.zero
        for child in children {
            recomputed.add(child.summary)
        }
        summary = recomputed
        return siblings
    }

    static func leafSplitPoint(in slice: Substring) -> String.Index {
        let count = slice.utf8.count

        if count <= maxChunkUTF8 {
            return slice.endIndex
        }

        return splitPoint(in: slice, targetUTF8: min((count + 1) / 2, maxChunkUTF8))
    }

    static func splitPoint(in slice: Substring, targetUTF8 target: Int) -> String.Index {
        let utf8 = slice.utf8

        var offset = target
        while offset > 0 {
            let candidate = utf8.index(utf8.startIndex, offsetBy: offset)
            if String.Index(candidate, within: slice) != nil {
                return candidate
            }
            offset -= 1
        }

        return utf8.index(utf8.startIndex, offsetBy: target)
    }
}
