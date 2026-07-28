extension TextRope {
    /// - Invariant: `utf16Offset` must be in `0...utf16Count`.
    public mutating func insert(_ string: String, at utf16Offset: Int) {
        if string.isEmpty { return }
        precondition(utf16Offset >= 0 && utf16Offset <= utf16Count, "insert offset \(utf16Offset) out of range 0...\(utf16Count)")
        ensureUnique()
        if root.isLeaf {
            spliceIntoLeaf(root, at: utf16Offset, content: string)
            if root.chunk.utf8.count > Node.maxChunkUTF8 {
                root = Self.buildTree(from: Self.chunkLeaves(from: root.chunk[...]))
            }
            return
        }
        let siblings = insertIntoNode(root, at: utf16Offset, content: string)
        if !siblings.isEmpty {
            root = Self.buildTree(from: [root] + siblings)
        }
    }

    private func insertIntoNode(_ node: Node, at utf16Offset: Int, content: String) -> [Node] {
        if node.isLeaf {
            if let sibling = insertIntoLeaf(node, at: utf16Offset, content: content) {
                return [sibling]
            }
            return []
        }

        var remaining = utf16Offset
        for i in 0..<node.children.count {
            let childUTF16 = node.children[i].summary.utf16
            if remaining < childUTF16 || i == node.children.count - 1 {
                node.ensureUniqueChild(at: i)
                let siblings = insertIntoNode(node.children[i], at: remaining, content: content)
                updateSummary(node)
                if !siblings.isEmpty {
                    node.children.insert(contentsOf: siblings, at: i + 1)
                    var j = i + 1
                    while j < node.children.count
                            && node.children[j].isLeaf
                            && node.children[j].chunk.utf8.count > Node.maxChunkUTF8 {
                        let extra = node.children[j].splitLeaf()
                        node.children.insert(extra, at: j + 1)
                        j += 1
                    }
                    updateSummary(node)
                    if node.children.count > Node.maxChildren {
                        return node.splitInner()
                    }
                }
                return []
            }
            remaining -= childUTF16
        }
        return []
    }

    private func insertIntoLeaf(_ node: Node, at utf16Offset: Int, content: String) -> Node? {
        spliceIntoLeaf(node, at: utf16Offset, content: content)

        if node.chunk.utf8.count > Node.maxChunkUTF8 {
            return node.splitLeaf()
        }
        return nil
    }

    private func spliceIntoLeaf(_ node: Node, at utf16Offset: Int, content: String) {
        let utf16View = node.chunk.utf16
        let insertIdx: String.Index
        if utf16Offset >= node.chunk.utf16.count {
            insertIdx = node.chunk.endIndex
        } else {
            insertIdx = utf16View.index(utf16View.startIndex, offsetBy: utf16Offset)
        }

        node.chunk.insert(contentsOf: content, at: insertIdx)
        node.summary = Summary.of(node.chunk)
    }

    private func updateSummary(_ node: Node) {
        var summary = Summary.zero
        if node.isLeaf {
            summary = Summary.of(node.chunk)
        } else {
            for child in node.children {
                summary.add(child.summary)
            }
        }
        node.summary = summary
    }
}
