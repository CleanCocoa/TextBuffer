public struct TextRope: Sendable {
    internal nonisolated(unsafe) var root: Node

    public init() {
        self.root = Node.emptyLeaf()
    }

    public var isEmpty: Bool { root.summary.utf8 == 0 }
    public var utf16Count: Int { root.summary.utf16 }
    public var utf8Count: Int { root.summary.utf8 }

    public var content: String {
        var result = ""
        func collect(_ node: Node) {
            if node.isLeaf {
                result += node.chunk
            } else {
                for child in node.children {
                    collect(child)
                }
            }
        }
        collect(root)
        return result
    }
}

extension TextRope: Equatable {
    public static func == (lhs: TextRope, rhs: TextRope) -> Bool {
        lhs.root === rhs.root || lhs.content == rhs.content
    }
}
