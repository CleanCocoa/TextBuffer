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

        redistributeStarvedChunks(in: &leaves)
        return leaves
    }

    /// `leadingChunkEnd` chooses each split in isolation, so a starved residual-band split
    /// can emit an undersized chunk even though the chunk carved just before it admits a
    /// conforming redistribution. ADR-012 judges starvation against each adjacent leaf
    /// (design D3/D6), so the run is repaired here; undersized *edge* chunks against
    /// pre-existing tree neighbors are the caller's job (`insertIntoNode`).
    private static func redistributeStarvedChunks(in leaves: inout [Node]) {
        var index = 1
        while index < leaves.count {
            if leaves[index].chunk.utf8.count < Node.minChunkUTF8 {
                let combined = leaves[index - 1].chunk + leaves[index].chunk
                if !Node.isBoundaryStarved(combined[...]) {
                    let replacements = Node.rebalancedChunks(in: combined[...]).map { Node.leaf(String($0)) }
                    leaves.replaceSubrange((index - 1)...index, with: replacements)
                    index = index - 1 + replacements.count
                    continue
                }
            }
            index += 1
        }
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
