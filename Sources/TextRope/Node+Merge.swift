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
    /// Detects an adjacent-subtree pair whose facing edge leaves include an undersized
    /// one that the cross-seam combination could conformingly absorb (DEF-017, design
    /// D1/D3). Adjacency in ADR-012's starvation predicate is **document order** over
    /// the flattened leaf sequence — which inner node groups two adjacent leaves is a
    /// batching artifact — so an undersized leaf at its parent's edge must be judged
    /// against the facing edge leaf of the adjacent subtree, exactly as the test-side
    /// `chunkSizeViolations` validator does. `Node.isBoundaryStarved` is the shared
    /// predicate (producer/validator agreement, as at `graphemeSeam` and
    /// `redistributeStarvedEdge`); the spine walks mirror `graphemeSeam(between:)`.
    static func absorbableStarvedEdge(between left: Node, and right: Node) -> Bool {
        var last = left
        while !last.isLeaf { last = last.children[last.children.count - 1] }

        var first = right
        while !first.isLeaf { first = first.children[0] }

        guard last.chunk.utf8.count < Node.minChunkUTF8
                || first.chunk.utf8.count < Node.minChunkUTF8 else { return false }

        let combined = last.chunk + first.chunk
        return !Node.isBoundaryStarved(combined[...])
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

        var chunks = Node.rebalancedChunks(in: combined[...]).map { String($0) }
        // Other-side consultation (DEF-017, design D2): an undersized chunk emitted into
        // `merged` exits the merge loop's field of view immediately, so a starved
        // combination's left output would otherwise be accepted against *that pair* only.
        // ADR-012 legalizes an undersized leaf only when starved against **each**
        // adjacent leaf, so make a single redistribution attempt with `merged.last`
        // before emitting. `Node.isBoundaryStarved` is the shared predicate — the
        // producer-side twin of the validator's `isStarvationJustified`, the same
        // pairing `redistributeStarvedEdge` and `graphemeSeam` maintain. Exactly one
        // attempt per emission, no rescan of `merged`, no loop: a successful attempt
        // emits only conforming chunks (`!isBoundaryStarved` guarantees the balanced
        // split exists), so it cannot cascade; a failed attempt *is* the starvation
        // proof for that side. The right-edge output (the returned chunk) needs no
        // counterpart: if undersized it stays `current`, and the existing loop consults
        // it rightward — or, at end of list, the `popLast` branch consults it leftward.
        if chunks.count > 1, chunks[0].utf8.count < Node.minChunkUTF8, let previous = merged.last {
            let pairCombined = previous.chunk + chunks[0]
            if !Node.isBoundaryStarved(pairCombined[...]) {
                merged.removeLast()
                var replacements = Node.rebalancedChunks(in: pairCombined[...]).map { String($0) }
                chunks[0] = replacements.removeLast()
                for replacement in replacements {
                    merged.append(Node.leaf(replacement))
                }
            }
        }
        for chunk in chunks.dropLast() {
            merged.append(Node.leaf(chunk))
        }
        return Node.leaf(String(chunks[chunks.count - 1]))
    }

    private static func mergeUndersizedInnerNodes(_ node: Node) {
        var merged = ContiguousArray<Node>()
        var i = 0

        while i < node.children.count {
            var current = node.children[i]
            i += 1

            // The `absorbableStarvedEdge` disjunct (DEF-017, design D3) funnels a
            // cross-parent absorbable pair through `combinedInner`, whose recursive
            // `mergeUndersizedChildren` makes the pair same-parent so `combinedLeaf`'s
            // other-side consultation repairs it. Termination: after the combine the
            // predicate is false for the repaired pair (conforming or two-sided
            // starved), and `combinedInner`'s mid-split regroups children without
            // changing leaf adjacency, so it cannot recreate the shape; `i` advances
            // monotonically as before. `mergeUndersizedLeaves`' combine condition
            // needs no such disjunct: an undersized leaf in a leaf-children array is
            // already combined by its undersize term, and the consultation at
            // `combinedLeaf` covers the leftward blind spot.
            while current.children.count < Node.minChildren
                    || (i < node.children.count
                            && (graphemeSeam(between: current, and: node.children[i])
                                    || absorbableStarvedEdge(between: current, and: node.children[i]))) {
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
