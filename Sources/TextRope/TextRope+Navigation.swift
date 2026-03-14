import Foundation

extension TextRope {
    internal struct LeafPosition {
        var node: Node
        var offsetInLeaf: Int
    }

    internal func findLeaf(utf16Offset: Int) -> LeafPosition {
        var remaining = utf16Offset
        var current = root

        while !current.isLeaf {
            var found = false
            for child in current.children {
                if remaining < child.summary.utf16 {
                    current = child
                    found = true
                    break
                }
                remaining -= child.summary.utf16
            }
            if !found {
                current = current.children[current.children.count - 1]
            }
        }

        return LeafPosition(node: current, offsetInLeaf: remaining)
    }

    public func content(in utf16Range: NSRange) -> String {
        if utf16Range.length == 0 { return "" }

        let startOffset = utf16Range.location
        let endOffset = utf16Range.location + utf16Range.length
        var result = ""
        var utf16Pos = 0

        func collect(_ node: Node) {
            if utf16Pos >= endOffset { return }
            let nodeEnd = utf16Pos + node.summary.utf16
            if nodeEnd <= startOffset {
                utf16Pos = nodeEnd
                return
            }

            if node.isLeaf {
                let localStart = max(0, startOffset - utf16Pos)
                let localEnd = min(node.summary.utf16, endOffset - utf16Pos)

                let utf16View = node.chunk.utf16
                let startIdx = utf16View.index(utf16View.startIndex, offsetBy: localStart)
                let endIdx = utf16View.index(utf16View.startIndex, offsetBy: localEnd)
                result += String(node.chunk[startIdx..<endIdx])

                utf16Pos = nodeEnd
            } else {
                for child in node.children {
                    if utf16Pos >= endOffset { break }
                    collect(child)
                }
            }
        }

        collect(root)
        return result
    }
}
