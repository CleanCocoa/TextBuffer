/// A B-tree based rope for efficient text storage and manipulation.
///
/// `TextRope` provides O(log n) insert, delete, and replace operations, making it well-suited
/// for large documents where `NSMutableString`'s O(n) mutations become a bottleneck.
///
/// The struct uses copy-on-write semantics and is `Sendable`. All positions and ranges use
/// UTF-16 code unit offsets (`Int` and half-open `Range<Int>`), so they translate mechanically
/// to and from the ranges Foundation and AppKit text APIs use. The TextRope target itself
/// depends on nothing but the Swift standard library; conveniences that accept Foundation's
/// range type come with the TextBuffer target.
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
    /// Two ropes are equal exactly when their contents are the same sequence of UTF-8
    /// code units.
    ///
    /// This is **code-unit equality**, and it is deliberately different from Swift's
    /// `String ==`, which decides by Unicode *canonical equivalence*. Contents a reader
    /// would see rendered identically are not equal here unless their code units agree:
    ///
    /// ```swift
    /// TextRope("é") == TextRope("e\u{301}")   // false — U+00E9 vs U+0065 U+0301
    /// "é" == "e\u{301}"                       // true  — Swift String ==
    /// ```
    ///
    /// The reason is congruence over this type's offset-addressed API: `a == b` must imply
    /// that `a` and `b` answer every count query identically and behave identically under
    /// the same operation at the same UTF-16 offset. Canonically equivalent contents can
    /// differ in ``utf16Count``, so canonical equality would not be a congruence.
    ///
    /// Use ``isCanonicallyEquivalent(to:)`` to ask the render-equality question instead,
    /// and ``isTriviallyIdentical(to:)`` for the O(1) affirmative fast path.
    ///
    /// Equality is decided in three tiers: root identity, then an O(1) summary
    /// early-out (differing `utf8`/`utf16`/`lines` counts prove differing content,
    /// since every summary field is a pure additive function of the text), then
    /// content comparison. Equal summaries do NOT imply equal content — permutations
    /// of the same bytes share a summary — so the content tier is mandatory. No term
    /// of the comparison may be shape-derived: ropes holding the same text over
    /// different leaf partitions compare equal.
    ///
    /// The tier-2 early-out is sound *because* tier 3 is code-unit: equal code units imply
    /// equal summaries, so differing summaries prove differing code units. Under canonical
    /// semantics the early-out would instead be unsound — `"é"` and `"e\u{301}"` are
    /// canonically equal while differing in `utf8` and `utf16`, so tier 2 would reject a
    /// pair the contract called equal.
    public static func == (lhs: TextRope, rhs: TextRope) -> Bool {
        if lhs.root === rhs.root { return true }
        guard lhs.root.summary == rhs.root.summary else { return false }
        // Tier 3 materializes both contents. Now that the relation is byte-wise it is
        // streamable — a leaf-pair zipper could decide it without allocating — but that
        // is deliberately a separate slice (DEF-010 ledger, deferred pending a TheArchive2
        // profile) so the semantic change and the performance change land independently.
        return lhs.content.utf8.elementsEqual(rhs.content.utf8)
    }
}

extension TextRope {
    /// Whether the two ropes hold canonically equivalent text — the render-equality
    /// question, asked deliberately.
    ///
    /// This is Swift `String ==` semantics: `true` when the two contents are equal under
    /// Unicode canonical equivalence, so `TextRope("é")` and `TextRope("e\u{301}")` are
    /// canonically equivalent even though they are not `==`.
    ///
    /// Route by the question you are asking. Use this predicate when you want to know
    /// whether two documents would show the same glyphs; use ``==(_:_:)`` when you want
    /// byte fidelity — which is what the offset-addressed API implies, since canonically
    /// equivalent contents can differ in ``utf16Count``.
    ///
    /// `==` implies this predicate; the converse does **not** hold.
    ///
    /// - Complexity: O(*n*) in document length, always. Unlike ``==(_:_:)`` there is no
    ///   summary early-out — no summary field is normalization-invariant — and canonical
    ///   equivalence has no streaming form, because normalization is not chunk-local.
    ///   This is the expensive predicate; do not call it per keystroke.
    public func isCanonicallyEquivalent(to other: TextRope) -> Bool {
        content == other.content
    }

    /// Whether the two ropes share the same underlying storage — equality's tier 1,
    /// exposed as an O(1) affirmative fast path.
    ///
    /// The contract is one-directional, in the SE-0494 sense:
    ///
    /// - `true` implies `==`. The two values are the same document, so any work that
    ///   depends only on content can be skipped.
    /// - `false` implies **nothing**. Two ropes holding identical code units report
    ///   `false` as soon as copy-on-write has given them separate roots.
    ///
    /// Never read a `false` result as inequality; use ``==(_:_:)`` for that.
    ///
    /// Defined on `TextRope` itself rather than deferring to a standard-library facility,
    /// so it carries no toolchain or availability condition and means exactly root identity.
    ///
    /// - Complexity: O(1). Reads no summary and materializes no content.
    public func isTriviallyIdentical(to other: TextRope) -> Bool {
        root === other.root
    }
}
