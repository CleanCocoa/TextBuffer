import XCTest
@testable import TextRope

func verifyTreeInvariants(_ rope: TextRope, context: String = "", file: StaticString = #filePath, line: UInt = #line) {
    let prefix = context.isEmpty ? "" : "\(context): "
    let root = rope.root
    verifyConsistentLeafDepth(root, prefix: prefix, file: file, line: line)
    verifyChildCounts(root, isRoot: true, prefix: prefix, file: file, line: line)
    verifyChunkSizes(root, prefix: prefix, file: file, line: line)
    verifyCRLFNotSplitAcrossLeaves(root, prefix: prefix, file: file, line: line)
    verifyLeafSeams(root, prefix: prefix, file: file, line: line)
    verifySummaries(root, prefix: prefix, file: file, line: line)
    verifyHeight(root, prefix: prefix, file: file, line: line)
}

private func verifyConsistentLeafDepth(_ root: TextRope.Node, prefix: String, file: StaticString, line: UInt) {
    var leafDepths: [Int] = []
    func walk(_ node: TextRope.Node, depth: Int) {
        if node.isLeaf {
            leafDepths.append(depth)
        } else {
            for child in node.children {
                walk(child, depth: depth + 1)
            }
        }
    }
    walk(root, depth: 0)
    let unique = Set(leafDepths)
    XCTAssertEqual(unique.count, 1, "\(prefix)Leaves at inconsistent depths: \(leafDepths)", file: file, line: line)
}

private func verifyChildCounts(_ node: TextRope.Node, isRoot: Bool, prefix: String, file: StaticString, line: UInt) {
    guard !node.isLeaf else { return }
    let count = node.children.count
    XCTAssertLessThanOrEqual(count, TextRope.Node.maxChildren, "\(prefix)Inner node has \(count) children, max is \(TextRope.Node.maxChildren)", file: file, line: line)
    if !isRoot {
        XCTAssertGreaterThanOrEqual(count, TextRope.Node.minChildren, "\(prefix)Non-root inner node has \(count) children, min is \(TextRope.Node.minChildren)", file: file, line: line)
    }
    for child in node.children {
        verifyChildCounts(child, isRoot: false, prefix: prefix, file: file, line: line)
    }
}

private func collectLeaves(_ node: TextRope.Node) -> [TextRope.Node] {
    if node.isLeaf { return [node] }
    var result: [TextRope.Node] = []
    for child in node.children {
        result.append(contentsOf: collectLeaves(child))
    }
    return result
}

private func verifyChunkSizes(_ root: TextRope.Node, prefix: String, file: StaticString, line: UInt) {
    for violation in chunkSizeViolations(in: root) {
        XCTFail("\(prefix)\(violation)", file: file, line: line)
    }
}

/// Exact ADR-012 chunk-size predicates — no fuzzy byte tolerances:
/// - A leaf may exceed `maxChunkUTF8` only when its chunk is a single grapheme cluster
///   (the whole-cluster leaf).
/// - A leaf may fall below `minChunkUTF8` only under provable boundary starvation: for
///   each adjacent leaf, the combined slice exceeds `maxChunkUTF8` **and** has no
///   `Character` boundary in its legal `[low, high]` window, so no conforming
///   redistribution exists. A leaf without neighbors (single-leaf tree) is vacuously
///   justified.
func chunkSizeViolations(in root: TextRope.Node) -> [String] {
    let leaves = collectLeaves(root)
    var violations: [String] = []
    for (index, leaf) in leaves.enumerated() {
        let size = leaf.chunk.utf8.count
        if size > TextRope.Node.maxChunkUTF8 && leaf.chunk.count > 1 {
            violations.append("Leaf \(index) has \(size) UTF-8 bytes and more than one Character, max is \(TextRope.Node.maxChunkUTF8)")
        }
        if size < TextRope.Node.minChunkUTF8 {
            for neighborIndex in [index - 1, index + 1] where leaves.indices.contains(neighborIndex) {
                let combined = neighborIndex < index
                    ? leaves[neighborIndex].chunk + leaf.chunk
                    : leaf.chunk + leaves[neighborIndex].chunk
                if !isStarvationJustified(combined: combined) {
                    violations.append("Leaf \(index) has \(size) UTF-8 bytes, min is \(TextRope.Node.minChunkUTF8), and redistribution with leaf \(neighborIndex) (combined \(combined.utf8.count) bytes) would conform")
                }
            }
        }
    }
    return violations
}

/// True when no conforming two-way split of `combined` exists (ADR-012 boundary
/// starvation): the combination is too large for one chunk, and its legal window
/// `[max(min, count - max), min(max, count - min)]` holds no `Character` boundary.
/// An empty window (`count > 2 * maxChunkUTF8`, reachable only next to an oversized
/// whole-cluster leaf) is trivially boundary-free.
private func isStarvationJustified(combined: String) -> Bool {
    let count = combined.utf8.count
    guard count > TextRope.Node.maxChunkUTF8 else { return false }
    let low = max(TextRope.Node.minChunkUTF8, count - TextRope.Node.maxChunkUTF8)
    let high = min(TextRope.Node.maxChunkUTF8, count - TextRope.Node.minChunkUTF8)
    guard low <= high else { return true }
    return TextRope.Node.boundary(in: combined[...], nearest: (count + 1) / 2, within: low...high) == nil
}

private func verifyLeafSeams(_ root: TextRope.Node, prefix: String, file: StaticString, line: UInt) {
    for violation in leafSeamViolations(in: root) {
        XCTFail("\(prefix)\(violation)", file: file, line: line)
    }
}

/// ADR-012: chunk seams always fall on `Character` boundaries. A seam inside a grapheme
/// cluster is unconditionally a violation — there is no starvation carve-out for seams.
func leafSeamViolations(in root: TextRope.Node) -> [String] {
    let leaves = collectLeaves(root)
    guard leaves.count > 1 else { return [] }
    let content = leaves.map(\.chunk).joined()
    let utf8 = content.utf8
    var violations: [String] = []
    var offset = 0
    for (index, leaf) in leaves.dropLast().enumerated() {
        offset += leaf.chunk.utf8.count
        let candidate = utf8.index(utf8.startIndex, offsetBy: offset)
        if String.Index(candidate, within: content) == nil {
            violations.append("Chunk seam after leaf \(index) at UTF-8 offset \(offset) falls inside a grapheme cluster")
        }
    }
    return violations
}

private func verifyCRLFNotSplitAcrossLeaves(_ root: TextRope.Node, prefix: String, file: StaticString, line: UInt) {
    let leaves = collectLeaves(root)
    guard leaves.count > 1 else { return }
    for i in 0..<(leaves.count - 1) {
        let splitPair = leaves[i].chunk.utf8.last == UInt8(ascii: "\r")
            && leaves[i + 1].chunk.utf8.first == UInt8(ascii: "\n")
        XCTAssertFalse(splitPair, "\(prefix)CRLF pair split across adjacent leaves \(i) and \(i + 1)", file: file, line: line)
    }
}

private func verifySummaries(_ node: TextRope.Node, prefix: String, file: StaticString, line: UInt) {
    if node.isLeaf {
        let expected = TextRope.Summary.of(node.chunk)
        XCTAssertEqual(node.summary, expected, "\(prefix)Leaf summary mismatch: stored \(node.summary), recomputed \(expected)", file: file, line: line)
    } else {
        var recomputed = TextRope.Summary.zero
        for child in node.children {
            verifySummaries(child, prefix: prefix, file: file, line: line)
            recomputed.add(child.summary)
        }
        XCTAssertEqual(node.summary, recomputed, "\(prefix)Inner node summary mismatch: stored \(node.summary), recomputed \(recomputed)", file: file, line: line)
    }
}

// MARK: - Validator predicate coverage (DEF-007)

/// The chunk-size and seam predicates must accept exactly the shapes ADR-012 legalizes
/// and reject everything else — no fuzzy byte tolerances.
final class TreeInvariantValidatorTests: XCTestCase {

    // MARK: Undersized leaves

    func testRejectsUndersizedLeafThatItsNeighborCouldAbsorb() {
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 1000)),
            TextRope.Node.leaf(String(repeating: "b", count: 1024)),
        ])
        XCTAssertFalse(
            chunkSizeViolations(in: root).isEmpty,
            "combined 2024 bytes fit a single conforming chunk; the undersized leaf is not starvation-justified"
        )
    }

    func testRejectsUndersizedLeafWhenRedistributionWindowHoldsABoundary() {
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 1000)),
            TextRope.Node.leaf(String(repeating: "b", count: 2048)),
        ])
        XCTAssertFalse(
            chunkSizeViolations(in: root).isEmpty,
            "the combined 3048-byte slice has a Character boundary at every offset of its [1024, 2024] window; redistribution would conform"
        )
    }

    func testAcceptsStarvedShapeFromManifestationThree() {
        // DEF-001 manifestation 3 leaves [1023, 1026]: the combined 2049-byte slice has no
        // Character boundary in its [1024, 1025] window (the emoji spans bytes [1023, 1027)),
        // so the undersized leaf is starvation-justified per ADR-012.
        let part2 = String(repeating: "c", count: 1022) + "\u{1F600}" + String(repeating: "d", count: 1022)
        var rope = TextRope(String(repeating: "a", count: 2048) + String(repeating: "b", count: 2048) + part2)

        rope.delete(in: 1000..<5095)

        let leafSizes = collectLeaves(rope.root).map { $0.chunk.utf8.count }
        XCTAssertEqual(leafSizes, [1023, 1026], "repro precondition changed; the starved shape no longer reproduces")
        XCTAssertEqual(chunkSizeViolations(in: rope.root), [], "the starved [1023, 1026] shape is legal under ADR-012")
        verifyTreeInvariants(rope, context: "manifestation 3 starved shape")
    }

    // MARK: Oversized leaves

    func testAcceptsOversizedLeafHoldingASingleGraphemeCluster() {
        let cluster = "e" + String(repeating: "\u{0301}", count: 1200)
        XCTAssertEqual(cluster.count, 1, "the fixture must be a single grapheme cluster")
        XCTAssertGreaterThan(cluster.utf8.count, TextRope.Node.maxChunkUTF8)
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 1024)),
            TextRope.Node.leaf(cluster),
        ])
        XCTAssertEqual(chunkSizeViolations(in: root), [], "a whole-cluster leaf may exceed maxChunkUTF8")
    }

    func testRejectsOversizedLeafSpanningMultipleCharacters() {
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 2049)),
            TextRope.Node.leaf(String(repeating: "b", count: 1024)),
        ])
        XCTAssertFalse(
            chunkSizeViolations(in: root).isEmpty,
            "a leaf above maxChunkUTF8 holding more than one Character is illegal unconditionally"
        )
    }

    // MARK: Seams

    func testRejectsChunkSeamInsideAGraphemeCluster() {
        // "e" + combining acute forms one Character across the seam: the seam offset is a
        // Unicode scalar boundary but not a Character boundary.
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 1023) + "e"),
            TextRope.Node.leaf("\u{0301}" + String(repeating: "b", count: 1023)),
        ])
        XCTAssertFalse(
            leafSeamViolations(in: root).isEmpty,
            "a seam between a base character and its combining mark falls inside a grapheme cluster"
        )
    }

    func testAcceptsChunkSeamsOnCharacterBoundaries() {
        let root = TextRope.Node.inner([
            TextRope.Node.leaf(String(repeating: "a", count: 1024)),
            TextRope.Node.leaf("\u{1F600}" + String(repeating: "b", count: 1020)),
        ])
        XCTAssertEqual(leafSeamViolations(in: root), [])
    }
}

private func verifyHeight(_ root: TextRope.Node, prefix: String, file: StaticString, line: UInt) {
    func actualHeight(_ node: TextRope.Node) -> UInt8 {
        if node.isLeaf { return 0 }
        var maxChild: UInt8 = 0
        for child in node.children {
            let h = actualHeight(child)
            XCTAssertEqual(child.height, h, "\(prefix)Child height mismatch: stored \(child.height), actual \(h)", file: file, line: line)
            maxChild = max(maxChild, h)
        }
        return maxChild + 1
    }
    let actual = actualHeight(root)
    XCTAssertEqual(root.height, actual, "\(prefix)Root height mismatch: stored \(root.height), actual \(actual)", file: file, line: line)
}
