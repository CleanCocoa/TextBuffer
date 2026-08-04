extension TextRope {
    /// Detects a grapheme seam between two adjacent subtrees (DEF-016): the left
    /// subtree's last `Character` and the right subtree's first `Character` join into a
    /// single grapheme cluster under Swift stdlib segmentation — their concatenation
    /// forms fewer than two `Character`s. `\r\n` is the named special case (one Swift
    /// `Character`), matched by the general rule instead of by byte comparison.
    ///
    /// Producer/validator pairing: this predicate must stay in agreement with the
    /// test-side `leafSeamViolations` validator (`TreeInvariantValidation.swift`) — the
    /// same pairing `Node.isBoundaryStarved` has for starvation. Swift stdlib
    /// segmentation only; the TextRope target is Foundation-free (ADR-013).
    static func graphemeSeam(between left: Node, and right: Node) -> Bool {
        var last = left
        while !last.isLeaf { last = last.children[last.children.count - 1] }
        guard let leftEdge = last.chunk.last else { return false }

        var first = right
        while !first.isLeaf { first = first.children[0] }
        guard let rightEdge = first.chunk.first else { return false }

        return (String(leftEdge) + String(rightEdge)).count < 2
    }
    static func mergeUndersizedChildren(_ node: Node) {
        guard !node.children.isEmpty else { return }

        if node.children[0].isLeaf {
            mergeUndersizedLeaves(node)
        } else {
            mergeUndersizedInnerNodes(node)
        }
    }

    private static func mergeUndersizedLeaves(_ node: Node) {
        var merged = ContiguousArray<Node>()
        var i = 0

        while i < node.children.count {
            var current = node.children[i]
            i += 1

            while current.chunk.utf8.count < Node.minChunkUTF8
                    || (i < node.children.count && graphemeSeam(between: current, and: node.children[i])) {
                if i < node.children.count {
                    current = combinedLeaf(current.chunk, node.children[i].chunk, redistributingInto: &merged)
                    i += 1
                } else if let previous = merged.popLast() {
                    let chunkBefore = current.chunk
                    current = combinedLeaf(previous.chunk, current.chunk, redistributingInto: &merged)
                    if current.chunk == chunkBefore && merged.last?.chunk == previous.chunk {
                        // Boundary starvation (ADR-012): redistribution is a fixed point, so
                        // the out-of-bounds leaf is accepted without retrying.
                        break
                    }
                } else {
                    break
                }
            }

            merged.append(current)
        }

        node.children = merged
    }

    private static func combinedLeaf(_ left: String, _ right: String, redistributingInto merged: inout ContiguousArray<Node>) -> Node {
        let combined = left + right
        if combined.utf8.count <= Node.maxChunkUTF8 {
            return Node.leaf(combined)
        }

        let chunks = Node.rebalancedChunks(in: combined[...])
        for chunk in chunks.dropLast() {
            merged.append(Node.leaf(String(chunk)))
        }
        return Node.leaf(String(chunks[chunks.count - 1]))
    }

    private static func mergeUndersizedInnerNodes(_ node: Node) {
        var merged = ContiguousArray<Node>()
        var i = 0

        while i < node.children.count {
            var current = node.children[i]
            i += 1

            while current.children.count < Node.minChildren
                    || (i < node.children.count && graphemeSeam(between: current, and: node.children[i])) {
                if i < node.children.count {
                    current = combinedInner(current, node.children[i], redistributingInto: &merged)
                    i += 1
                } else if let previous = merged.popLast() {
                    current = combinedInner(previous, current, redistributingInto: &merged)
                } else {
                    break
                }
            }

            merged.append(current)
        }

        node.children = merged
    }

    private static func combinedInner(_ left: Node, _ right: Node, redistributingInto merged: inout ContiguousArray<Node>) -> Node {
        var children = left.children
        children.append(contentsOf: right.children)
        let combined = Node.inner(children)
        mergeUndersizedChildren(combined)
        recalculateSummary(combined)

        if combined.children.count <= Node.maxChildren {
            return combined
        }

        let mid = combined.children.count / 2
        merged.append(Node.inner(ContiguousArray(combined.children[0..<mid])))
        return Node.inner(ContiguousArray(combined.children[mid...]))
    }
}
