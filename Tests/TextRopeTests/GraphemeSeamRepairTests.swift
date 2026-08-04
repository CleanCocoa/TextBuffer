import XCTest
@testable import TextRope

/// DEF-016 regression coverage: a grapheme cluster can come to span a leaf seam by
/// **adjacency change** — an insert placing a grapheme extender at leaf-local offset 0,
/// or a delete removing the base character that separated two leaves whose edge
/// `Character`s join. Seam repair must cover every such cluster, with CRLF (`\r\n` is one
/// Swift `Character`) as the named special case. Judged via the `leafSeamViolations` /
/// `chunkSizeViolations` validators (ADR-012 predicates; no byte-range pins on repair
/// output — a repair MAY legally emit a starvation-proven undersized leaf or a
/// whole-cluster oversized leaf).
///
/// `NodeSplitPointTests.swift` stays the DEF-001 split-point suite; adjacency repair is
/// a distinct mechanism.
final class GraphemeSeamRepairTests: XCTestCase {
    private func leafChunkSizes(_ rope: TextRope) -> [Int] {
        func collect(_ node: TextRope.Node) -> [Int] {
            node.isLeaf ? [node.chunk.utf8.count] : node.children.flatMap(collect)
        }
        return collect(rope.root)
    }

    // MARK: - DEF-016 repro 1: insert splices a combining mark at a leaf boundary

    func testInsertingCombiningMarkAtLeafBoundaryLeavesNoSeamInsideCluster() {
        var rope = TextRope(String(repeating: "a", count: 4096))
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048], "repro precondition changed; construction no longer yields the [2048, 2048] shape")

        rope.insert("\u{301}", at: 2048)

        let oracle = String(repeating: "a", count: 2048) + "\u{301}" + String(repeating: "a", count: 2048)
        XCTAssertEqual(leafSeamViolations(in: rope.root), [], "the cluster a\\u{301} must not span a leaf seam")
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [])
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf16Count, oracle.utf16.count)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
    }

    // MARK: - DEF-016 repro 2: delete removes the base character separating two leaves

    func testDeletingBaseCharacterRejoinsExposedGraphemeSeam() {
        let base = String(repeating: "a", count: 2048) + "b\u{301}" + String(repeating: "c", count: 2045)
        var rope = TextRope(base)
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048], "repro precondition changed; construction no longer yields the [2048, 2048] shape")

        rope.delete(in: 2048..<2049)

        let oracle = String(repeating: "a", count: 2048) + "\u{301}" + String(repeating: "c", count: 2045)
        XCTAssertEqual(leafSeamViolations(in: rope.root), [], "the cluster a\\u{301} exposed by deleting the base b must not span a leaf seam")
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [])
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf16Count, oracle.utf16.count)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
    }

    // MARK: - End-to-end repair legality (full validator, ADR-012 predicates only)

    /// A repair MAY legally produce ADR-012's starved shapes (minimal-shortfall undersized
    /// leaf, whole-cluster oversized leaf); legality is asserted via the full validator's
    /// predicate helpers, never via byte-range pins on the repaired leaves.
    func testInsertReproPassesFullTreeInvariantValidation() {
        var rope = TextRope(String(repeating: "a", count: 4096))
        rope.insert("\u{301}", at: 2048)
        verifyTreeInvariants(rope, context: "insert combining mark at leaf boundary")
    }

    func testDeleteReproPassesFullTreeInvariantValidation() {
        var rope = TextRope(String(repeating: "a", count: 2048) + "b\u{301}" + String(repeating: "c", count: 2045))
        rope.delete(in: 2048..<2049)
        verifyTreeInvariants(rope, context: "delete base before combining mark at leaf boundary")
    }

    // MARK: - Predicate boundary cases: ZWJ and variation selector

    func testDeletingCharacterBeforeZWJAtLeafBoundaryRepairsSeam() {
        // "b\u{200D}" is one cluster (no break before ZWJ), so construction splits
        // between the a-run and it; deleting the "b" exposes a\u{200D} across the seam.
        let base = String(repeating: "a", count: 2048) + "b\u{200D}" + String(repeating: "c", count: 2044)
        var rope = TextRope(base)
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048], "repro precondition changed; construction no longer yields the [2048, 2048] shape")

        rope.delete(in: 2048..<2049)

        let oracle = String(repeating: "a", count: 2048) + "\u{200D}" + String(repeating: "c", count: 2044)
        XCTAssertEqual(leafSeamViolations(in: rope.root), [], "a ZWJ joins leftward; the exposed seam must be repaired")
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
        verifyTreeInvariants(rope, context: "ZWJ exposed at seam by delete")
    }

    func testInsertingVariationSelectorAtLeafBoundaryRepairsSeam() {
        var rope = TextRope(String(repeating: "a", count: 4096))
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048], "repro precondition changed; construction no longer yields the [2048, 2048] shape")

        rope.insert("\u{FE0F}", at: 2048)

        let oracle = String(repeating: "a", count: 2048) + "\u{FE0F}" + String(repeating: "a", count: 2048)
        XCTAssertEqual(leafSeamViolations(in: rope.root), [], "a variation selector joins leftward; the spliced seam must be repaired")
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
        verifyTreeInvariants(rope, context: "variation selector inserted at leaf boundary")
    }

    // MARK: - Regional-indicator parity (design D1)

    /// A seam between a complete flag pair and a following lone RI is a `Character`
    /// boundary of the whole content — legal, not a violation. Hand-built tree:
    /// mutations cannot reach this shape check.
    func testValidatorAcceptsSeamBetweenCompleteFlagAndLoneRegionalIndicator() {
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 2040) + "\u{1F1E9}\u{1F1EA}"),
            TextRope.Node.leaf("\u{1F1EB}" + String(repeating: "c", count: 2044)),
        ])
        XCTAssertEqual(leafSeamViolations(in: root), [], "a complete flag followed by a lone RI breaks at the seam; this is legal")
    }

    /// A lone RI ending one leaf with a lone RI starting the next joins into a flag —
    /// the seam falls inside the cluster. Hand-built tree pins the validator side.
    func testValidatorRejectsSeamBetweenTwoLoneRegionalIndicators() {
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 2044) + "\u{1F1E9}"),
            TextRope.Node.leaf("\u{1F1EA}" + String(repeating: "c", count: 2044)),
        ])
        XCTAssertFalse(leafSeamViolations(in: root).isEmpty, "two lone RIs across a seam form one flag cluster; the seam is a violation")
    }

    /// Producer side, legality half: deleting the separator so a complete flag ends up
    /// adjacent to a lone RI must NOT trigger a gratuitous repair — the seam is legal.
    func testDeleteExposingCompleteFlagBeforeLoneRegionalIndicatorIsNotRepaired() {
        let base = String(repeating: "a", count: 2040) + "\u{1F1E9}\u{1F1EA}" + "b" + "\u{1F1EB}" + String(repeating: "c", count: 2043)
        var rope = TextRope(base)
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048], "repro precondition changed; construction no longer yields the [2048, 2048] shape")

        rope.delete(in: 2044..<2045)

        let oracle = String(repeating: "a", count: 2040) + "\u{1F1E9}\u{1F1EA}" + "\u{1F1EB}" + String(repeating: "c", count: 2043)
        XCTAssertEqual(leafSeamViolations(in: rope.root), [])
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2047], "the legal flag | lone-RI seam must not be repaired into a different shape")
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
    }

    /// Producer side, repair half: deleting the separator between two lone RIs joins
    /// them into a flag across the seam — must be repaired.
    func testDeleteExposingTwoLoneRegionalIndicatorsAcrossSeamIsRepaired() {
        let base = String(repeating: "a", count: 2044) + "\u{1F1E9}" + "b" + "\u{1F1EA}" + String(repeating: "c", count: 2043)
        var rope = TextRope(base)
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048], "repro precondition changed; construction no longer yields the [2048, 2048] shape")

        rope.delete(in: 2046..<2047)

        let oracle = String(repeating: "a", count: 2044) + "\u{1F1E9}" + "\u{1F1EA}" + String(repeating: "c", count: 2043)
        XCTAssertEqual(leafSeamViolations(in: rope.root), [], "two lone RIs joined into one flag across the seam must be recombined into one leaf")
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
        verifyTreeInvariants(rope, context: "lone RI | lone RI seam repaired")
    }

    // MARK: - CRLF non-regression: the special case still repairs under the general rule

    func testCRLFSeamRepairStillFiresUnderGeneralizedPredicate() {
        // fix-rope-split-point manifestation-1 shape: \r ends the first full leaf, \n is
        // inserted at the seam. CRLF is now the special case of the general rule.
        let base = String(repeating: "a", count: 2047) + "\r" + String(repeating: "b", count: 2047)
        var rope = TextRope(base)

        rope.insert("\n", at: 2048)

        let oracle = String(repeating: "a", count: 2047) + "\r\n" + String(repeating: "b", count: 2047)
        XCTAssertEqual(leafSeamViolations(in: rope.root), [])
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [])
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.utf8Count, oracle.utf8.count)
        verifyTreeInvariants(rope, context: "CRLF seam repair under generalized predicate")
    }
}
