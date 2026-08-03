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
            let chunkEnd = Node.leadingChunkEnd(in: remaining)
            leaves.append(Node.leaf(String(remaining[remaining.startIndex..<chunkEnd])))
            remaining = remaining[chunkEnd...]
        }

        return leaves
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
