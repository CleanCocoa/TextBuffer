extension TextRope {
    public init(_ string: String) {
        if string.isEmpty {
            self.init()
            return
        }

        self.init()
        self.root = Self.buildTree(from: Self.chunkLeaves(from: string[...]))
    }

    static func chunkLeaves(from slice: Substring) -> [Node] {
        var leaves: [Node] = []
        var remaining = slice

        while !remaining.isEmpty {
            let chunkEnd = Self.chunkEnd(in: remaining)
            leaves.append(Node.leaf(String(remaining[remaining.startIndex..<chunkEnd])))
            remaining = remaining[chunkEnd...]
        }

        return leaves
    }

    private static func chunkEnd(in slice: Substring) -> String.Index {
        let utf8 = slice.utf8
        let count = utf8.count

        if count <= Node.maxChunkUTF8 {
            return slice.endIndex
        }

        let target: Int
        if count < Node.maxChunkUTF8 + Node.minChunkUTF8 {
            target = (count + 1) / 2
        } else {
            target = Node.maxChunkUTF8
        }

        let candidate = utf8.index(utf8.startIndex, offsetBy: target)
        let prev = utf8.index(before: candidate)
        if utf8[prev] == UInt8(ascii: "\r") && utf8[candidate] == UInt8(ascii: "\n") {
            return prev
        }
        return candidate
    }

    static func buildTree(from nodes: [Node]) -> Node {
        precondition(!nodes.isEmpty)
        var level = nodes
        while level.count > 1 {
            var nextLevel: [Node] = []
            var i = 0
            while i < level.count {
                let remaining = level.count - i
                let take: Int
                if remaining > Node.maxChildren && remaining < Node.maxChildren + Node.minChildren {
                    take = (remaining + 1) / 2
                } else {
                    take = min(Node.maxChildren, remaining)
                }
                let group = ContiguousArray(level[i..<(i + take)])
                nextLevel.append(Node.inner(group))
                i += take
            }
            level = nextLevel
        }
        return level[0]
    }
}
