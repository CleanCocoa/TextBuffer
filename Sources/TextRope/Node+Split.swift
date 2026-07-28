extension TextRope.Node {
    func splitLeaf() -> TextRope.Node {
        let mid = Self.leafSplitPoint(in: chunk[...])
        let left = String(chunk[chunk.startIndex..<mid])
        let right = String(chunk[mid..<chunk.endIndex])
        chunk = left
        summary = TextRope.Summary.of(left)
        return TextRope.Node.leaf(right)
    }

    func splitInner() -> TextRope.Node {
        let mid = children.count / 2
        let rightChildren = ContiguousArray(children[mid...])
        children.removeSubrange(mid...)
        var recomputed = TextRope.Summary.zero
        for child in children {
            recomputed.add(child.summary)
        }
        summary = recomputed
        return TextRope.Node.inner(rightChildren)
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
