extension TextRope {
    public init(_ string: String) {
        if string.isEmpty {
            self.init()
            return
        }

        var leaves: [Node] = []
        var remaining = string[...]

        while !remaining.isEmpty {
            let chunkEnd = Node.leafSplitPoint(in: remaining)
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
