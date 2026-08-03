// Split-point regime (ADR-012, grapheme-first chunk bounds): every split point falls on a
// `Character` boundary — never inside a grapheme cluster, not even at a Unicode scalar
// boundary. The chunk byte bounds `[minChunkUTF8, maxChunkUTF8]` hold whenever a conforming
// boundary exists; under boundary starvation the nearest-boundary minimal-deviation split is
// taken, and a single cluster larger than `maxChunkUTF8` occupies one whole-cluster leaf of
// whatever size it needs. Starvation is not exotic: a width-1 window is starved by any 2-byte
// cluster, so a plain `\r\n` at a 4096-byte combination triggers it deterministically.
extension TextRope.Node {
    func splitLeaf() -> TextRope.Node {
        let mid = Self.leadingChunkEnd(in: chunk[...])
        let left = String(chunk[chunk.startIndex..<mid])
        let right = String(chunk[mid..<chunk.endIndex])
        chunk = left
        summary = TextRope.Summary.of(left)
        return TextRope.Node.leaf(right)
    }

    func splitInner() -> [TextRope.Node] {
        let total = children.count
        let groupCount = (total + Self.maxChildren - 1) / Self.maxChildren
        let base = total / groupCount
        let extra = total % groupCount

        var siblings: [TextRope.Node] = []
        var start = base + (extra > 0 ? 1 : 0)
        let firstGroupEnd = start
        for group in 1..<groupCount {
            let size = base + (group < extra ? 1 : 0)
            siblings.append(TextRope.Node.inner(ContiguousArray(children[start..<(start + size)])))
            start += size
        }

        children.removeSubrange(firstGroupEnd...)
        var recomputed = TextRope.Summary.zero
        for child in children {
            recomputed.add(child.summary)
        }
        summary = recomputed
        return siblings
    }

    static func leafSplitPoint(in slice: Substring) -> String.Index {
        leadingChunkEnd(in: slice)
    }

    /// End of the first chunk to carve off `slice` (design D2). Shared by construction
    /// chunking and insert-overflow leaf splits; the caller re-chunks the remainder.
    static func leadingChunkEnd(in slice: Substring) -> String.Index {
        let count = slice.utf8.count

        if count <= maxChunkUTF8 {
            return slice.endIndex
        }

        if count >= maxChunkUTF8 + minChunkUTF8 {
            if let greedy = boundary(in: slice, nearest: maxChunkUTF8, within: 1...maxChunkUTF8) {
                return greedy
            }
            // A single cluster covers [1, maxChunkUTF8]: emit it whole as an oversized
            // whole-cluster leaf.
            return slice.index(after: slice.startIndex)
        }

        // Residual band (maxChunkUTF8 < count < maxChunkUTF8 + minChunkUTF8): balanced split.
        if let balanced = boundary(in: slice, nearest: (count + 1) / 2, within: minChunkUTF8...(count - minChunkUTF8)) {
            return balanced
        }
        if let starved = minimalShortfallSplitPoint(in: slice) {
            return starved
        }
        // A single cluster spans the whole hard window: split before it when possible, so the
        // caller re-chunks the remainder into a whole-cluster leaf.
        let windowStart = count - maxChunkUTF8
        if windowStart >= 2, let beforeCluster = boundary(in: slice, nearest: windowStart - 1, within: 1...(windowStart - 1)) {
            return beforeCluster
        }
        return slice.index(after: slice.startIndex)
    }

    /// Redistributes an oversized merge/seam combination into 1-3 chunks (design D1):
    /// one chunk when the slice fits, a balanced two-way split when the legal window
    /// `[low, high]` holds a boundary, a balanced three-way split when it does not and three
    /// conforming chunks are feasible, and otherwise the ADR-012 minimal-deviation split.
    static func rebalancedChunks(in slice: Substring) -> [Substring] {
        let count = slice.utf8.count

        if count <= maxChunkUTF8 {
            return [slice]
        }

        let low = max(minChunkUTF8, count - maxChunkUTF8)
        let high = min(maxChunkUTF8, count - minChunkUTF8)
        if let mid = boundary(in: slice, nearest: (count + 1) / 2, within: low...high) {
            return [slice[slice.startIndex..<mid], slice[mid...]]
        }

        if count >= 3 * minChunkUTF8,
           let first = boundary(in: slice, nearest: count / 3, within: 1...(count - 2)) {
            let firstOffset = slice.utf8.distance(from: slice.utf8.startIndex, to: first)
            if let second = boundary(in: slice, nearest: 2 * count / 3, within: (firstOffset + 1)...(count - 1)) {
                return [slice[slice.startIndex..<first], slice[first..<second], slice[second...]]
            }
        }

        if let mid = minimalShortfallSplitPoint(in: slice) {
            return [slice[slice.startIndex..<mid], slice[mid...]]
        }

        // A single cluster spans the whole hard window: emit it whole (ADR-012), with any
        // prefix and suffix as starvation-justified chunks.
        let windowStart = count - maxChunkUTF8
        var clusterStart = slice.startIndex
        if windowStart >= 2, let beforeCluster = boundary(in: slice, nearest: windowStart - 1, within: 1...(windowStart - 1)) {
            clusterStart = beforeCluster
        }
        let clusterEnd = slice.index(after: clusterStart)
        var chunks: [Substring] = []
        if clusterStart > slice.startIndex {
            chunks.append(slice[slice.startIndex..<clusterStart])
        }
        chunks.append(slice[clusterStart..<clusterEnd])
        if clusterEnd < slice.endIndex {
            chunks.append(slice[clusterEnd...])
        }
        return chunks
    }

    /// ADR-012 boundary starvation for a two-leaf combination: true when no conforming
    /// redistribution of `combined` exists — the combination is too large for one chunk and
    /// its legal window `[max(min, count - max), min(max, count - min)]` holds no `Character`
    /// boundary. An empty window (`count > 2 * maxChunkUTF8`, reachable only next to an
    /// oversized whole-cluster leaf) is trivially boundary-free. This is the exact predicate
    /// the tree-invariant validator applies per adjacent leaf (design D3/D6), so an
    /// undersized chunk may be emitted only where this returns true.
    static func isBoundaryStarved(_ combined: Substring) -> Bool {
        let count = combined.utf8.count
        guard count > maxChunkUTF8 else { return false }
        let low = max(minChunkUTF8, count - maxChunkUTF8)
        let high = min(maxChunkUTF8, count - minChunkUTF8)
        guard low <= high else { return true }
        return boundary(in: combined, nearest: (count + 1) / 2, within: low...high) == nil
    }

    /// Bidirectional `Character`-boundary search over the closed UTF-8 offset range `window`,
    /// nearest to `target`, ties resolving to the lower offset. Never yields a bare Unicode
    /// scalar boundary.
    static func boundary(in slice: Substring, nearest target: Int, within window: ClosedRange<Int>) -> String.Index? {
        let utf8 = slice.utf8
        var backward = min(max(target, window.lowerBound), window.upperBound)
        var forward = backward + 1
        while backward >= window.lowerBound || forward <= window.upperBound {
            let backwardDistance = backward >= window.lowerBound ? abs(target - backward) : Int.max
            let forwardDistance = forward <= window.upperBound ? abs(forward - target) : Int.max
            if backwardDistance <= forwardDistance {
                let candidate = utf8.index(utf8.startIndex, offsetBy: backward)
                if String.Index(candidate, within: slice) != nil {
                    return candidate
                }
                backward -= 1
            } else {
                let candidate = utf8.index(utf8.startIndex, offsetBy: forward)
                if String.Index(candidate, within: slice) != nil {
                    return candidate
                }
                forward += 1
            }
        }
        return nil
    }

    /// ADR-012 minimal-deviation split for a starved balanced window: among the `Character`
    /// boundaries in the hard window `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]`,
    /// picks the one minimizing `shortfall(p) = max(0, min - p) + max(0, min - (count - p))`,
    /// ties resolving to the lower offset. Returns nil when a single cluster spans the whole
    /// hard window.
    static func minimalShortfallSplitPoint(in slice: Substring) -> String.Index? {
        let count = slice.utf8.count
        let low = max(1, count - maxChunkUTF8)
        let high = min(maxChunkUTF8, count - 1)
        guard low <= high else { return nil }
        let utf8 = slice.utf8

        var below = min(minChunkUTF8 - 1, high)
        var above = max(count - minChunkUTF8 + 1, low)
        while below >= low || above <= high {
            let belowShortfall = below >= low ? shortfall(of: below, count: count) : Int.max
            let aboveShortfall = above <= high ? shortfall(of: above, count: count) : Int.max
            if belowShortfall <= aboveShortfall {
                let candidate = utf8.index(utf8.startIndex, offsetBy: below)
                if String.Index(candidate, within: slice) != nil {
                    return candidate
                }
                below -= 1
            } else {
                let candidate = utf8.index(utf8.startIndex, offsetBy: above)
                if String.Index(candidate, within: slice) != nil {
                    return candidate
                }
                above += 1
            }
        }
        return nil
    }

    private static func shortfall(of splitOffset: Int, count: Int) -> Int {
        max(0, minChunkUTF8 - splitOffset) + max(0, minChunkUTF8 - (count - splitOffset))
    }
}
