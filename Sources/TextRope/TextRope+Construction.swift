extension TextRope {
    public init(_ string: String) {
        if string.isEmpty {
            self.init()
            return
        }

        var leaves: [Node] = []
        var remaining = string[...]

        while !remaining.isEmpty {
            let chunkEnd = splitPoint(in: remaining)
            leaves.append(Node.leaf(String(remaining[remaining.startIndex..<chunkEnd])))
            remaining = remaining[chunkEnd...]
        }

        self.init()
        self.root = Self.buildTree(from: leaves)
    }

    private static func buildTree(from nodes: [Node]) -> Node {
        precondition(!nodes.isEmpty)
        var level = nodes
        while level.count > 1 {
            var nextLevel: [Node] = []
            var i = 0
            while i < level.count {
                let end = min(i + Node.maxChildren, level.count)
                let group = ContiguousArray(level[i..<end])
                nextLevel.append(Node.inner(group))
                i = end
            }
            level = nextLevel
        }
        return level[0]
    }
}

private func splitPoint(in slice: Substring) -> String.Index {
    let utf8 = slice.utf8
    let maxBytes = TextRope.Node.maxChunkUTF8

    if utf8.count <= maxBytes {
        return slice.endIndex
    }

    let candidateIdx = utf8.index(utf8.startIndex, offsetBy: maxBytes)
    let candidate = candidateIdx

    if candidate > slice.startIndex {
        let prev = utf8.index(before: candidate)
        if utf8[prev] == UInt8(ascii: "\r") && candidate < slice.endIndex && utf8[candidate] == UInt8(ascii: "\n") {
            return utf8.index(after: candidate)
        }
    }

    return candidate
}
