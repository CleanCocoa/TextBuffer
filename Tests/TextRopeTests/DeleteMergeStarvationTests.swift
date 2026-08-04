import XCTest
@testable import TextRope

/// DEF-017: the delete-path merge accepted a starved combination's undersized output
/// without consulting the *other-side* adjacent leaf, violating ADR-012's
/// per-adjacent-leaf starvation predicate (undersized only when starved against
/// **each** document-order neighbor — the exact predicate `chunkSizeViolations`
/// applies). Deterministic repros distilled from stress seed `0xDEF007` with the
/// extender alphabet, iteration 48, without the stress machinery.
final class DeleteMergeStarvationTests: XCTestCase {

    /// Flattened document-order leaf sizes in UTF-8 bytes.
    private func leafUTF8Sizes(_ node: TextRope.Node) -> [Int] {
        if node.isLeaf { return [node.chunk.utf8.count] }
        return node.children.flatMap { leafUTF8Sizes($0) }
    }

    private func delete(_ utf16Range: Range<Int>, from oracle: inout String) {
        let start = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: utf16Range.lowerBound)
        let end = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: utf16Range.upperBound)
        oracle.removeSubrange(start..<end)
    }

    /// The minimal three-leaf repro (task 1.1): the delete leaves the middle pair at
    /// `[1023, 1027]`, whose 2050-byte combination is starved (the `\u{1F389}` spans
    /// its `[1024, 1026]` window), while the 1074-byte *left* neighbor's 2097-byte
    /// combination has `Character` boundaries throughout its `[1024, 1073]` window.
    /// The undersized 1023 output must be redistributed leftward, not accepted.
    /// (The conforming outcome is e.g. `[1049, 1048, 1027]` — asserted via the
    /// validator predicates, not pinned byte shapes.)
    func testStarvedPairOutputRedistributesWithSameParentLeftNeighbor() {
        let a = String(repeating: "a", count: 1074)
        let b = String(repeating: "b", count: 1024)
        let c = String(repeating: "c", count: 7) + "\u{1F389}" + String(repeating: "d", count: 1023)

        var rope = TextRope()
        rope.root = .inner([.leaf(a), .leaf(b), .leaf(c)])
        var oracle = a + b + c

        // Shape precondition: if this fails, the repro has silently stopped reproducing.
        XCTAssertEqual(leafUTF8Sizes(rope.root), [1074, 1024, 1034], "repro precondition changed")
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [], "repro precondition changed")
        verifyTreeInvariants(rope, context: "precondition")

        // One UTF-16 unit off the middle leaf's tail (offset 2097) plus the seven "c"s.
        rope.delete(in: 2097..<2105)
        delete(2097..<2105, from: &oracle)

        XCTAssertEqual(chunkSizeViolations(in: rope.root), [])
        XCTAssertEqual(leafSeamViolations(in: rope.root), [])
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf16Count, oracle.utf16.count)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
        verifyTreeInvariants(rope, context: "after seam delete")
    }

    /// The cross-parent variant (task 1.2, design D1/D3): the absorbing 1074-byte
    /// neighbor is the rightmost leaf of `P1` while the starved pair sits at `P2`'s
    /// left edge. `P2`'s within-parent merge emits the 1023 leaf at its own left edge
    /// with `merged` empty, `P2` keeps 4 children (`minChildren`) so no child-count
    /// trigger opens `deleteFromInner(root)`'s gate — only the `absorbableStarvedEdge`
    /// or-term can reach this shape.
    func testStarvedPairOutputRedistributesAcrossParentBoundary() {
        let a = String(repeating: "a", count: 1074)
        let b = String(repeating: "b", count: 1024)
        let c = String(repeating: "c", count: 7) + "\u{1F389}" + String(repeating: "d", count: 1023)

        var rope = TextRope()
        let p1 = TextRope.Node.inner([
            .leaf(String(repeating: "e", count: 1500)),
            .leaf(String(repeating: "f", count: 1500)),
            .leaf(String(repeating: "g", count: 1500)),
            .leaf(a),
        ])
        let p2 = TextRope.Node.inner([
            .leaf(b),
            .leaf(c),
            .leaf(String(repeating: "h", count: 1500)),
            .leaf(String(repeating: "i", count: 1500)),
        ])
        rope.root = .inner([p1, p2])
        var oracle = String(repeating: "e", count: 1500)
            + String(repeating: "f", count: 1500)
            + String(repeating: "g", count: 1500)
            + a + b + c
            + String(repeating: "h", count: 1500)
            + String(repeating: "i", count: 1500)

        // Shape precondition: both inner nodes at minChildren, seam recipe intact.
        XCTAssertEqual(
            leafUTF8Sizes(rope.root),
            [1500, 1500, 1500, 1074, 1024, 1034, 1500, 1500],
            "repro precondition changed"
        )
        XCTAssertEqual(rope.root.children[0].children.count, TextRope.Node.minChildren)
        XCTAssertEqual(rope.root.children[1].children.count, TextRope.Node.minChildren)
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [], "repro precondition changed")
        verifyTreeInvariants(rope, context: "precondition")

        // Same seam recipe as the minimal repro, shifted by P1's 4,574 leading units.
        rope.delete(in: 6597..<6605)
        delete(6597..<6605, from: &oracle)

        XCTAssertEqual(chunkSizeViolations(in: rope.root), [])
        XCTAssertEqual(leafSeamViolations(in: rope.root), [])
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf16Count, oracle.utf16.count)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
        verifyTreeInvariants(rope, context: "after cross-parent seam delete")
    }

    /// Fixed-point non-regression guard (task 1.3, design D4): a trio starved on
    /// *both* sides. The left combination (1026 + 1023 = 2049) is starved — its
    /// `[1024, 1025]` window sits inside leaf 0's trailing `\u{1F389}` — and the
    /// right combination (2050) is starved as in the minimal repro. The new
    /// consultation must accept the undersized leaf (provably starved against each
    /// adjacent leaf) and must not oscillate its shape under further operations.
    func testUndersizedOutputStarvedAgainstBothNeighborsIsAcceptedWithoutOscillation() {
        let a = String(repeating: "a", count: 1022) + "\u{1F389}"
        let b = String(repeating: "b", count: 1024)
        let c = String(repeating: "c", count: 7) + "\u{1F389}" + String(repeating: "d", count: 1023)

        var rope = TextRope()
        rope.root = .inner([.leaf(a), .leaf(b), .leaf(c)])
        var oracle = a + b + c

        // Shape precondition, including the delete offsets: leaf 0's trailing emoji is
        // one Character but two UTF-16 units, so the b|c seam sits at 1024 + 1024.
        XCTAssertEqual(leafUTF8Sizes(rope.root), [1026, 1024, 1034], "repro precondition changed")
        XCTAssertEqual(rope.root.children[0].summary.utf16, 1024, "repro precondition changed")
        XCTAssertEqual(rope.root.children[1].summary.utf16, 1024, "repro precondition changed")
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [], "repro precondition changed")
        verifyTreeInvariants(rope, context: "precondition")

        // Same seam recipe: one unit off leaf 1's tail plus the seven "c"s.
        rope.delete(in: 2047..<2055)
        delete(2047..<2055, from: &oracle)

        let starvedShape = leafUTF8Sizes(rope.root)
        XCTAssertEqual(starvedShape, [1026, 1023, 1027], "expected the two-sided starved fixed point")
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [], "the two-sided starved shape is legal under ADR-012")
        XCTAssertEqual(rope.content, oracle)
        verifyTreeInvariants(rope, context: "after seam delete")

        // One further unrelated operation must not disturb the starved pair. A
        // document-*end* append would be a related operation for this trio: it grows the
        // starved pair's right member, widening the right combination's window onto the
        // emoji-end boundary and legitimately un-starving the pair. A document-start
        // insert leaves both starvation proofs intact (the left combination's window
        // [1024, 1026] stays inside leaf 0's trailing emoji span).
        rope.insert("y", at: 0)
        oracle = "y" + oracle

        XCTAssertEqual(
            Array(leafUTF8Sizes(rope.root)[1..<3]), Array(starvedShape[1..<3]),
            "a genuinely two-sided starved pair must be a fixed point — no oscillation"
        )
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [])
        XCTAssertEqual(rope.content, oracle)
        verifyTreeInvariants(rope, context: "after unrelated append")
    }
}
