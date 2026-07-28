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
        let utf8 = slice.utf8
        let maxBytes = maxChunkUTF8

        if utf8.count <= maxBytes {
            return slice.endIndex
        }

        let candidate = utf8.index(utf8.startIndex, offsetBy: maxBytes)

        if candidate > slice.startIndex {
            let prev = utf8.index(before: candidate)
            if utf8[prev] == UInt8(ascii: "\r") && candidate < slice.endIndex && utf8[candidate] == UInt8(ascii: "\n") {
                return utf8.index(after: candidate)
            }
        }

        return candidate
    }
}
