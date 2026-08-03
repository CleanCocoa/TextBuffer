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
    /// Equality is decided in three tiers: root identity, then an O(1) summary
    /// early-out (differing `utf8`/`utf16`/`lines` counts prove differing content,
    /// since every summary field is a pure additive function of the text), then
    /// content comparison. Equal summaries do NOT imply equal content — permutations
    /// of the same bytes share a summary — so the content tier is mandatory. No term
    /// of the comparison may be shape-derived: ropes holding the same text over
    /// different leaf partitions compare equal.
    public static func == (lhs: TextRope, rhs: TextRope) -> Bool {
        if lhs.root === rhs.root { return true }
        guard lhs.root.summary == rhs.root.summary else { return false }
        return lhs.content == rhs.content
    }
}
