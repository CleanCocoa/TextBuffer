import Foundation

extension TextRope {
    public mutating func delete(in utf16Range: NSRange) {
        if utf16Range.length == 0 { return }
        ensureUnique()

        let start = utf16Range.location
        let end = utf16Range.location + utf16Range.length

        _ = Self.deleteFromNode(root, utf16Start: start, utf16End: end)

        while !root.isLeaf && root.children.count == 1 {
            root = root.children[0]
        }

        if root.summary.utf8 == 0 {
            root = Node.emptyLeaf()
        }
    }

    @discardableResult
    private static func deleteFromNode(_ node: Node, utf16Start: Int, utf16End: Int) -> Bool {
        if node.isLeaf {
            return deleteFromLeaf(node, utf16Start: utf16Start, utf16End: utf16End)
        } else {
            return deleteFromInner(node, utf16Start: utf16Start, utf16End: utf16End)
        }
    }

    private static func deleteFromLeaf(_ node: Node, utf16Start: Int, utf16End: Int) -> Bool {
        let localStart = max(0, utf16Start)
        let localEnd = min(node.summary.utf16, utf16End)

        if localStart >= localEnd { return false }

        let utf16View = node.chunk.utf16
        let startIdx = utf16View.index(utf16View.startIndex, offsetBy: localStart)
        let endIdx = utf16View.index(utf16View.startIndex, offsetBy: localEnd)

        node.chunk.removeSubrange(startIdx..<endIdx)
        node.summary = Summary.of(node.chunk)

        return node.chunk.utf8.count < Node.minChunkUTF8
    }

    private static func deleteFromInner(_ node: Node, utf16Start: Int, utf16End: Int) -> Bool {
        var utf16Pos = 0
        var indicesToRemove: [Int] = []

        for i in 0..<node.children.count {
            let child = node.children[i]
            let childEnd = utf16Pos + child.summary.utf16

            if utf16Pos >= utf16End { break }

            if childEnd <= utf16Start {
                utf16Pos = childEnd
                continue
            }

            let localStart = utf16Start - utf16Pos
            let localEnd = utf16End - utf16Pos

            if localStart <= 0 && localEnd >= child.summary.utf16 {
                indicesToRemove.append(i)
            } else {
                node.ensureUniqueChild(at: i)
                deleteFromNode(node.children[i], utf16Start: localStart, utf16End: localEnd)
            }

            utf16Pos = childEnd
        }

        for i in indicesToRemove.reversed() {
            node.children.remove(at: i)
        }

        mergeUndersizedChildren(node)
        recalculateSummary(node)

        return node.children.count < Node.minChildren
    }

    private static func mergeUndersizedChildren(_ node: Node) {
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

            while i < node.children.count && current.chunk.utf8.count < Node.minChunkUTF8 {
                let next = node.children[i]
                let combined = current.chunk + next.chunk
                if combined.utf8.count <= Node.maxChunkUTF8 {
                    current = Node.leaf(combined)
                    i += 1
                } else {
                    break
                }
            }

            if current.chunk.utf8.count > Node.maxChunkUTF8 {
                let sub = current.chunk[...]
                var remaining = sub
                while !remaining.isEmpty {
                    let splitEnd = leafSplitPoint(in: remaining)
                    merged.append(Node.leaf(String(remaining[remaining.startIndex..<splitEnd])))
                    remaining = remaining[splitEnd...]
                }
            } else {
                merged.append(current)
            }
        }

        node.children = merged
    }

    private static func mergeUndersizedInnerNodes(_ node: Node) {
        var merged = ContiguousArray<Node>()
        var i = 0

        while i < node.children.count {
            var current = node.children[i]
            i += 1

            while i < node.children.count && current.children.count < Node.minChildren {
                let next = node.children[i]
                let combinedCount = current.children.count + next.children.count
                if combinedCount <= Node.maxChildren {
                    var combinedChildren = current.children
                    combinedChildren.append(contentsOf: next.children)
                    current = Node.inner(combinedChildren)
                    i += 1
                } else {
                    break
                }
            }

            if current.children.count > Node.maxChildren {
                let mid = current.children.count / 2
                let left = ContiguousArray(current.children[0..<mid])
                let right = ContiguousArray(current.children[mid...])
                merged.append(Node.inner(left))
                merged.append(Node.inner(right))
            } else {
                merged.append(current)
            }
        }

        node.children = merged
    }

    private static func recalculateSummary(_ node: Node) {
        var summary = Summary.zero
        for child in node.children {
            summary.add(child.summary)
        }
        node.summary = summary
    }

    private static func leafSplitPoint(in slice: Substring) -> String.Index {
        let utf8 = slice.utf8
        let maxBytes = Node.maxChunkUTF8

        if utf8.count <= maxBytes {
            return slice.endIndex
        }

        let candidate = utf8.index(utf8.startIndex, offsetBy: maxBytes)

        if candidate > slice.startIndex {
            let prev = utf8.index(before: candidate)
            if utf8[prev] == UInt8(ascii: "\r") && candidate < slice.endIndex && utf8[candidate] == UInt8(ascii: "\n") {
                return utf8.index(after: candidate)
            }
        }

        return candidate
    }
}
