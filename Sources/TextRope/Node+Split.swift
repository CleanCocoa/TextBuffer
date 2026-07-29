extension TextRope.Node {
    func splitLeaf() -> TextRope.Node {
        let mid = Self.leafSplitPoint(in: chunk[...])
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
        let count = slice.utf8.count

        if count <= maxChunkUTF8 {
            return slice.endIndex
        }

        return splitPoint(in: slice, targetUTF8: min((count + 1) / 2, maxChunkUTF8))
    }

    static func balancedSplitPoint(in slice: Substring) -> String.Index {
        let count = slice.utf8.count
        let low = max(minChunkUTF8, count - maxChunkUTF8)
        let high = min(maxChunkUTF8, count - minChunkUTF8)
        let target = (count + 1) / 2
        let utf8 = slice.utf8

        var backward = min(target, high)
        var forward = backward + 1
        while backward >= low || forward <= high {
            if backward >= low {
                let candidate = utf8.index(utf8.startIndex, offsetBy: backward)
                if String.Index(candidate, within: slice) != nil {
                    return candidate
                }
                backward -= 1
            }
            if forward <= high {
                let candidate = utf8.index(utf8.startIndex, offsetBy: forward)
                if String.Index(candidate, within: slice) != nil {
                    return candidate
                }
                forward += 1
            }
        }

        // Constraint: reached only when no Character boundary exists in [low, high], i.e. a single grapheme cluster straddles the whole redistribution window (e.g. a degenerate ZWJ chain); the backward-only splitPoint walk can then undershoot `low` and produce an undersized left chunk.
        return splitPoint(in: slice, targetUTF8: target)
    }

    static func splitPoint(in slice: Substring, targetUTF8 target: Int) -> String.Index {
        let utf8 = slice.utf8

        var offset = target
        while offset > 0 {
            let candidate = utf8.index(utf8.startIndex, offsetBy: offset)
            if String.Index(candidate, within: slice) != nil {
                return candidate
            }
            offset -= 1
        }

        // Constraint: reached only when no Character boundary exists in (0, target], i.e. the slice starts with a single grapheme cluster wider than `target` bytes (> maxChunkUTF8 in practice, e.g. a degenerate ZWJ chain); the returned index then falls mid-character, splitting that cluster across chunks.
        return utf8.index(utf8.startIndex, offsetBy: target)
    }
}
