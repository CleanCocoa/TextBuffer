import XCTest
import Foundation
@testable import TextRope

/// DEF-001 regression coverage: split points must respect the legal chunk-size window
/// (ADR-012 grapheme-first bounds — splits at `Character` boundaries only, bounds yield
/// only under provable boundary starvation).
final class NodeSplitPointTests: XCTestCase {
    private func leafChunks(_ rope: TextRope) -> [String] {
        func collect(_ node: TextRope.Node) -> [String] {
            node.isLeaf ? [node.chunk] : node.children.flatMap(collect)
        }
        return collect(rope.root)
    }

    private func leafChunkSizes(_ rope: TextRope) -> [Int] {
        leafChunks(rope).map(\.utf8.count)
    }

    private func assertLeavesWithinChunkBounds(_ rope: TextRope, file: StaticString = #filePath, line: UInt = #line) {
        for (index, size) in leafChunkSizes(rope).enumerated() {
            XCTAssertLessThanOrEqual(size, TextRope.Node.maxChunkUTF8, "leaf \(index) has \(size) UTF-8 bytes, above max", file: file, line: line)
            XCTAssertGreaterThanOrEqual(size, TextRope.Node.minChunkUTF8, "leaf \(index) has \(size) UTF-8 bytes, below min", file: file, line: line)
        }
    }

    private func assertLeafSeamsFallOnCharacterBoundaries(_ rope: TextRope, file: StaticString = #filePath, line: UInt = #line) {
        let content = rope.content
        let utf8 = content.utf8
        var offset = 0
        for size in leafChunkSizes(rope).dropLast() {
            offset += size
            let candidate = utf8.index(utf8.startIndex, offsetBy: offset)
            XCTAssertNotNil(String.Index(candidate, within: content), "leaf seam at UTF-8 offset \(offset) falls inside a grapheme cluster", file: file, line: line)
        }
    }

    private func assertNoCRLFSplitAcrossLeaves(_ rope: TextRope, file: StaticString = #filePath, line: UInt = #line) {
        let chunks = leafChunks(rope)
        for i in 0..<max(0, chunks.count - 1) {
            let splitPair = chunks[i].utf8.last == UInt8(ascii: "\r") && chunks[i + 1].utf8.first == UInt8(ascii: "\n")
            XCTAssertFalse(splitPair, "CRLF pair split across leaves \(i) and \(i + 1)", file: file, line: line)
        }
    }

    // MARK: - DEF-001 manifestation 1: insert CRLF seam repair on a 4096-byte combination

    func testInsertingLFAfterCRAcrossFullLeavesRebalancesWithinChunkBounds() {
        let base = String(repeating: "a", count: 2047) + "\r" + String(repeating: "b", count: 2047)
        var rope = TextRope(base)

        rope.insert("\n", at: 2048)

        let expected = String(repeating: "a", count: 2047) + "\r\n" + String(repeating: "b", count: 2047)
        XCTAssertEqual(rope.content, expected)
        assertLeavesWithinChunkBounds(rope)
        assertNoCRLFSplitAcrossLeaves(rope)
        assertLeafSeamsFallOnCharacterBoundaries(rope)
    }

    // MARK: - DEF-001 manifestation 2: delete rejoining two full leaves across a CRLF seam

    func testDeleteRejoiningCRLFAcrossFullLeavesRebalancesWithinChunkBounds() {
        let a = String(repeating: "a", count: 2047) + "\r"
        let m = String(repeating: "m", count: 2048)
        let b = "\n" + String(repeating: "b", count: 2047)
        var rope = TextRope(a + m + b)
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048, 2048], "construction precondition changed; the repro no longer reproduces")

        rope.delete(in: NSRange(location: 2048, length: 2048))

        XCTAssertEqual(rope.content, a + b)
        assertLeavesWithinChunkBounds(rope)
        assertNoCRLFSplitAcrossLeaves(rope)
        assertLeafSeamsFallOnCharacterBoundaries(rope)
    }

    // MARK: - DEF-001 manifestation 3: boundary starvation in the residual band (ADR-012)

    func testDeleteRedistributionUnderBoundaryStarvationIsMinimalDeviationFixedPoint() {
        let part2 = String(repeating: "c", count: 1022) + "\u{1F600}" + String(repeating: "d", count: 1022)
        var rope = TextRope(String(repeating: "a", count: 2048) + String(repeating: "b", count: 2048) + part2)

        rope.delete(in: NSRange(location: 1000, length: 4095))

        let expected = String(repeating: "a", count: 1000) + String(repeating: "c", count: 23) + "\u{1F600}" + String(repeating: "d", count: 1022)
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(expected.utf8.count, 2049)
        for size in leafChunkSizes(rope) {
            XCTAssertLessThanOrEqual(size, TextRope.Node.maxChunkUTF8)
        }
        XCTAssertEqual(leafChunkSizes(rope), [1023, 1026])
        assertLeafSeamsFallOnCharacterBoundaries(rope)

        // Why [1023, 1026] is the ADR-012 minimal-deviation outcome: the combined 2049-byte
        // slice has no Character boundary in the legal window [1024, 1025] (the emoji spans
        // bytes [1023, 1027) — boundary starvation) ...
        let utf8 = expected.utf8
        for offset in 1024...1025 {
            let candidate = utf8.index(utf8.startIndex, offsetBy: offset)
            XCTAssertNil(String.Index(candidate, within: expected), "offset \(offset) must sit inside the straddling cluster for this repro")
        }
        // ... and the only alternative boundary 1027 leaves a 1022-byte tail (shortfall 2 vs 1).
        let alternative = utf8.index(utf8.startIndex, offsetBy: 1027)
        XCTAssertNotNil(String.Index(alternative, within: expected))
        let shortfallAt1023 = TextRope.Node.minChunkUTF8 - 1023
        let shortfallAt1027 = TextRope.Node.minChunkUTF8 - (2049 - 1027)
        XCTAssertLessThan(shortfallAt1023, shortfallAt1027, "1023 must be the minimal-shortfall boundary")

        // Re-running the merge over the same starved pair must not retry the redistribution:
        // the shape is a stable fixed point (ADR-012 merge no-retry).
        rope.insert("x", at: 0)
        rope.delete(in: NSRange(location: 0, length: 1))
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(leafChunkSizes(rope), [1023, 1026], "starved shape must be a stable fixed point across operations")
    }

    // MARK: - DEF-001 manifestation 4: backward-only walk undershoots the minimum

    func testLeafSplitPointPrefersForwardBoundaryWithSmallerShortfall() {
        // 4-byte scalar straddling the midpoint at bytes [1022, 1026), 2049 bytes total.
        let chunk = String(repeating: "a", count: 1022) + "\u{1F600}" + String(repeating: "b", count: 1023)
        XCTAssertEqual(chunk.utf8.count, 2049)

        let split = TextRope.Node.leafSplitPoint(in: chunk[...])

        let offset = chunk.utf8.distance(from: chunk.utf8.startIndex, to: split)
        XCTAssertEqual(offset, 1026, "boundary 1026 (left 1026, right 1023; shortfall 1) beats today's 1022 (shortfall 2)")
        XCTAssertEqual(String(chunk[chunk.startIndex..<split]) + String(chunk[split...]), chunk)
    }

    // MARK: - Small CRLF-seam combination must stay one leaf

    func testRepairCRLFSeamKeepsSmallCombinationAsOneLeaf() {
        let left = TextRope.Node.leaf(String(repeating: "a", count: 49) + "\r")
        let right = TextRope.Node.leaf("\n" + String(repeating: "b", count: 49))
        var rope = TextRope()
        rope.root = TextRope.Node.inner([left, right])

        rope.insert("x", at: 100)

        let expected = String(repeating: "a", count: 49) + "\r\n" + String(repeating: "b", count: 49) + "x"
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(leafChunkSizes(rope), [101], "a combination well under maxChunkUTF8 must come back as one leaf, not bisected")
        assertNoCRLFSplitAcrossLeaves(rope)
    }

    // MARK: - Construction-path twin of manifestation 4

    func testConstructionBalancedSplitFindsForwardBoundaryWhenBackwardWalkUndershootsMinimum() {
        // 8-byte emoji modifier sequence spanning bytes [1023, 1031): the backward-only walk
        // lands at 1023 (< minChunkUTF8) although 1031 sits inside the legal window.
        let cluster = "\u{1F44D}\u{1F3FD}"
        XCTAssertEqual(cluster.utf8.count, 8)
        XCTAssertEqual(cluster.count, 1)
        let input = String(repeating: "a", count: 1023) + cluster + String(repeating: "b", count: 1029)
        XCTAssertEqual(input.utf8.count, 2060)

        let rope = TextRope(input)

        XCTAssertEqual(rope.content, input)
        assertLeavesWithinChunkBounds(rope)
        assertLeafSeamsFallOnCharacterBoundaries(rope)
    }

    func testConstructionGreedyChunkBoundaryInsideMultiByteScalarKeepsChunksWithinBounds() {
        // Greedy branch (count >= maxChunkUTF8 + minChunkUTF8) with a cluster straddling
        // the maxChunkUTF8 boundary.
        let cluster = "\u{1F44D}\u{1F3FD}"
        let input = String(repeating: "a", count: 2046) + cluster + String(repeating: "b", count: 1500)
        XCTAssertEqual(input.utf8.count, 3554)

        let rope = TextRope(input)

        XCTAssertEqual(rope.content, input)
        assertLeavesWithinChunkBounds(rope)
        assertLeafSeamsFallOnCharacterBoundaries(rope)
    }

    // MARK: - rebalancedChunks window properties (design.md arithmetic)

    private func assertChunks(_ chunks: [Substring], roundTrip input: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(chunks.map(String.init).joined(), input, "chunks must concatenate back to the input", file: file, line: line)
        var offset = 0
        for chunk in chunks.dropLast() {
            offset += chunk.utf8.count
            let candidate = input.utf8.index(input.utf8.startIndex, offsetBy: offset)
            XCTAssertNotNil(String.Index(candidate, within: input), "chunk seam at UTF-8 offset \(offset) falls inside a grapheme cluster", file: file, line: line)
        }
    }

    func testRebalancedChunksOnASCIISlicesSplitsWithinWindow() {
        for count in [2048, 2049, 3072, 4095, 4096] {
            let input = String(repeating: "a", count: count)
            let chunks = TextRope.Node.rebalancedChunks(in: input[...])

            if count <= TextRope.Node.maxChunkUTF8 {
                XCTAssertEqual(chunks.count, 1, "count \(count) fits one chunk")
            } else {
                XCTAssertEqual(chunks.count, 2, "count \(count): the all-ASCII window holds a boundary")
                for chunk in chunks {
                    XCTAssertLessThanOrEqual(chunk.utf8.count, TextRope.Node.maxChunkUTF8, "count \(count)")
                    XCTAssertGreaterThanOrEqual(chunk.utf8.count, TextRope.Node.minChunkUTF8, "count \(count)")
                }
            }
            assertChunks(chunks, roundTrip: input)
        }
    }

    func testRebalancedChunksSplitsThreeWaysWhenCRLFStarvesTheWindowAtMaxCombined() {
        // count == 4096, window [2048, 2048] is exactly the CR/LF interior.
        let input = String(repeating: "a", count: 2047) + "\r\n" + String(repeating: "b", count: 2047)
        XCTAssertEqual(input.utf8.count, 4096)

        let chunks = TextRope.Node.rebalancedChunks(in: input[...])

        XCTAssertEqual(chunks.map(\.utf8.count), [1365, 1365, 1366])
        for chunk in chunks {
            XCTAssertLessThanOrEqual(chunk.utf8.count, TextRope.Node.maxChunkUTF8)
            XCTAssertGreaterThanOrEqual(chunk.utf8.count, TextRope.Node.minChunkUTF8)
        }
        XCTAssertTrue(chunks.contains { $0.contains("\r\n") }, "the CRLF pair must stay intact inside one chunk")
        assertChunks(chunks, roundTrip: input)
    }

    func testRebalancedChunksSplitsThreeWaysWhenScalarStarvesTheNarrowWindowAt4095() {
        // count == 4095, window [2047, 2048]; a 3-byte scalar spans bytes [2046, 2049).
        let input = String(repeating: "a", count: 2046) + "\u{20AC}" + String(repeating: "b", count: 2046)
        XCTAssertEqual(input.utf8.count, 4095)

        let chunks = TextRope.Node.rebalancedChunks(in: input[...])

        XCTAssertEqual(chunks.map(\.utf8.count), [1365, 1365, 1365])
        assertChunks(chunks, roundTrip: input)
    }

    func testRebalancedChunksTakesMinimalDeviationTwoWaySplitInResidualBand() {
        // count == 2049, window [1024, 1025]; a 4-byte scalar spans bytes [1022, 1026).
        // No three-way split is feasible (2049 < 3 * minChunkUTF8): minimal deviation picks
        // boundary 1026 (shortfall 1) over 1022 (shortfall 2).
        let input = String(repeating: "a", count: 1022) + "\u{1F600}" + String(repeating: "b", count: 1023)
        XCTAssertEqual(input.utf8.count, 2049)

        let chunks = TextRope.Node.rebalancedChunks(in: input[...])

        XCTAssertEqual(chunks.map(\.utf8.count), [1026, 1023])
        assertChunks(chunks, roundTrip: input)
    }

    // MARK: - Whole-cluster oversized leaf (ADR-012)

    private static let oversizedCluster = "e" + String(repeating: "\u{0301}", count: 1200)

    func testConstructionKeepsOversizedGraphemeClusterWholeInOneLeaf() {
        let cluster = Self.oversizedCluster
        XCTAssertEqual(cluster.count, 1, "the fixture must be a single grapheme cluster")
        XCTAssertGreaterThan(cluster.utf8.count, TextRope.Node.maxChunkUTF8)

        let rope = TextRope(cluster)

        XCTAssertEqual(rope.content, cluster)
        XCTAssertEqual(leafChunkSizes(rope), [cluster.utf8.count], "an oversized cluster must occupy exactly one whole-cluster leaf")
        assertLeafSeamsFallOnCharacterBoundaries(rope)
    }

    func testInsertOverflowKeepsOversizedGraphemeClusterWholeInOneLeaf() {
        let cluster = Self.oversizedCluster
        var rope = TextRope(String(repeating: "a", count: 2048))

        rope.insert(cluster, at: 1024)

        let expected = String(repeating: "a", count: 1024) + cluster + String(repeating: "a", count: 1024)
        XCTAssertEqual(rope.content, expected)
        XCTAssertTrue(leafChunks(rope).contains(cluster), "the oversized cluster must sit whole inside exactly one leaf")
        assertLeafSeamsFallOnCharacterBoundaries(rope)
        for chunk in leafChunks(rope) where chunk != cluster {
            XCTAssertLessThanOrEqual(chunk.utf8.count, TextRope.Node.maxChunkUTF8, "only the whole-cluster leaf may exceed maxChunkUTF8")
        }
    }
}
