extension TextRope {
    internal final class Node {
        var summary: Summary
        var height: UInt8
        var chunk: String
        var children: ContiguousArray<Node>

        static let maxChildren = 8
        static let minChildren = 4
        static let maxChunkUTF8 = 2048
        static let minChunkUTF8 = 1024

        init(summary: Summary, height: UInt8, chunk: String, children: ContiguousArray<Node>) {
            self.summary = summary
            self.height = height
            self.chunk = chunk
            self.children = children
        }

        static func leaf(_ chunk: String) -> Node {
            Node(
                summary: Summary.of(chunk),
                height: 0,
                chunk: chunk,
                children: []
            )
        }

        static func inner(_ children: ContiguousArray<Node>) -> Node {
            var summary = Summary.zero
            var maxHeight: UInt8 = 0
            for child in children {
                summary.add(child.summary)
                maxHeight = max(maxHeight, child.height)
            }
            return Node(
                summary: summary,
                height: maxHeight + 1,
                chunk: "",
                children: children
            )
        }

        static func emptyLeaf() -> Node {
            leaf("")
        }

        var isLeaf: Bool { height == 0 }

        func shallowCopy() -> Node {
            Node(
                summary: summary,
                height: height,
                chunk: chunk,
                children: ContiguousArray(children)
            )
        }

        func ensureUniqueChild(at index: Int) {
            var child = children[index]
            if !isKnownUniquelyReferenced(&child) {
                child = child.shallowCopy()
            }
            children[index] = child
        }
    }
}
