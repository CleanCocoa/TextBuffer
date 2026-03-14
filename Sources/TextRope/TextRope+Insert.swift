extension TextRope {
    public mutating func insert(_ string: String, at utf16Offset: Int) {
        if string.isEmpty { return }
        ensureUnique()
        if let sibling = insertIntoNode(root, at: utf16Offset, content: string) {
            root = Node.inner(ContiguousArray([root, sibling]))
        }
    }

    private func insertIntoNode(_ node: Node, at utf16Offset: Int, content: String) -> Node? {
        if node.isLeaf {
            return insertIntoLeaf(node, at: utf16Offset, content: content)
        }

        var remaining = utf16Offset
        for i in 0..<node.children.count {
            let childUTF16 = node.children[i].summary.utf16
            if remaining < childUTF16 || i == node.children.count - 1 {
                node.ensureUniqueChild(at: i)
                let sibling = insertIntoNode(node.children[i], at: remaining, content: content)
                updateSummary(node)
                if let sibling {
                    node.children.insert(sibling, at: i + 1)
                    updateSummary(node)
                    if node.children.count > Node.maxChildren {
                        return splitInner(node)
                    }
                }
                return nil
            }
            remaining -= childUTF16
        }
        return nil
    }

    private func insertIntoLeaf(_ node: Node, at utf16Offset: Int, content: String) -> Node? {
        let utf16View = node.chunk.utf16
        let insertIdx: String.Index
        if utf16Offset >= node.chunk.utf16.count {
            insertIdx = node.chunk.endIndex
        } else {
            insertIdx = utf16View.index(utf16View.startIndex, offsetBy: utf16Offset)
        }

        node.chunk.insert(contentsOf: content, at: insertIdx)
        node.summary = Summary.of(node.chunk)

        if node.chunk.utf8.count > Node.maxChunkUTF8 {
            return splitLeaf(node)
        }
        return nil
    }

    private func splitLeaf(_ node: Node) -> Node {
        let chunk = node.chunk
        let mid = leafSplitPoint(in: chunk)
        let left = String(chunk[chunk.startIndex..<mid])
        let right = String(chunk[mid..<chunk.endIndex])
        node.chunk = left
        node.summary = Summary.of(left)
        return Node.leaf(right)
    }

    private func splitInner(_ node: Node) -> Node {
        let mid = node.children.count / 2
        let rightChildren = ContiguousArray(node.children[mid...])
        node.children.removeSubrange(mid...)
        updateSummary(node)
        return Node.inner(rightChildren)
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

private func leafSplitPoint(in string: String) -> String.Index {
    let utf8 = string.utf8
    let maxBytes = TextRope.Node.maxChunkUTF8

    if utf8.count <= maxBytes {
        return string.endIndex
    }

    let candidate = utf8.index(utf8.startIndex, offsetBy: maxBytes)

    if candidate > string.startIndex {
        let prev = utf8.index(before: candidate)
        if utf8[prev] == UInt8(ascii: "\r") && candidate < string.endIndex && utf8[candidate] == UInt8(ascii: "\n") {
            return utf8.index(after: candidate)
        }
    }

    return candidate
}
