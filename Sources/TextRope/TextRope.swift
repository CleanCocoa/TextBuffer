/// A B-tree based rope for efficient text storage and manipulation.
///
/// `TextRope` provides O(log n) insert, delete, and replace operations, making it well-suited
/// for large documents where `NSMutableString`'s O(n) mutations become a bottleneck.
///
/// The struct uses copy-on-write semantics and is `Sendable`. All positions and ranges use
/// UTF-16 offsets (`Int` and `NSRange`) for compatibility with Foundation and AppKit text APIs.
///
/// `TextRope` is used internally by `RopeBuffer` and `SendableRopeBuffer` in the TextBuffer library.
/// Import the `TextRope` module directly when you need a standalone text storage primitive
/// without the buffer protocol API.
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
