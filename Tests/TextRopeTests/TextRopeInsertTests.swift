import XCTest
import Testing
@testable import TextRope

final class TextRopeInsertTests: XCTestCase {
    func testInsertAtStart() {
        var rope = TextRope("hello")
        rope.insert("X", at: 0)
        XCTAssertEqual(rope.content, "Xhello")
    }

    func testInsertAtEnd() {
        var rope = TextRope("hello")
        rope.insert("X", at: 5)
        XCTAssertEqual(rope.content, "helloX")
    }

    func testInsertAtMiddle() {
        var rope = TextRope("hello")
        rope.insert("X", at: 2)
        XCTAssertEqual(rope.content, "heXllo")
    }

    func testInsertEmptyString() {
        var rope = TextRope("hello")
        rope.insert("", at: 2)
        XCTAssertEqual(rope.content, "hello")
    }

    func testInsertEmptyStringAtInBoundsOffsetsIsNoOp() {
        for offset in [0, 3, 5] {
            var rope = TextRope("hello")
            rope.insert("", at: offset)
            XCTAssertEqual(rope.content, "hello", "insert(\"\", at: \(offset)) must be a no-op")
            XCTAssertEqual(rope.utf16Count, 5, "insert(\"\", at: \(offset)) must be a no-op")
        }
    }

    func testInsertCausingLeafSplit() {
        var rope = TextRope("a")
        let large = String(repeating: "B", count: 2500)
        rope.insert(large, at: 1)
        XCTAssertEqual(rope.content, "a" + large)
        XCTAssertEqual(rope.utf8Count, 2501)
        verifyTreeInvariants(rope)
    }

    func testInsertLargeStringIntoSingleLeafRope() {
        var rope = TextRope("a")
        let large = String(repeating: "B", count: 10 * 1024)
        rope.insert(large, at: 1)
        XCTAssertEqual(rope.content, "a" + large)
        XCTAssertEqual(rope.utf8Count, 10241)
        verifyTreeInvariants(rope)
    }

    func testInsertHugeStringIntoFullInnerNode() {
        let base = String(repeating: "A", count: 8 * 2048)
        var rope = TextRope(base)
        verifyTreeInvariants(rope)
        let insert = String(repeating: "Z", count: 100 * 1024)
        rope.insert(insert, at: 0)
        XCTAssertEqual(rope.content, insert + base)
        XCTAssertEqual(rope.utf8Count, base.utf8.count + insert.utf8.count)
        verifyTreeInvariants(rope)
    }

    func testInsertIntoFullInteriorLeafSplitsWithBothHalvesAboveMinimum() {
        let base = String(repeating: "A", count: 4 * 2048)
        var rope = TextRope(base)
        verifyTreeInvariants(rope)
        rope.insert("X", at: 2500)
        var expected = base
        expected.insert("X", at: expected.index(expected.startIndex, offsetBy: 2500))
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.utf8Count, 4 * 2048 + 1)
        verifyTreeInvariants(rope)
    }

    func testInsertMultiByteCharacter() {
        var rope = TextRope("abc")
        rope.insert("\u{1F600}", at: 1)
        XCTAssertEqual(rope.content, "a\u{1F600}bc")
        XCTAssertEqual(rope.utf16Count, 5)
    }

    func testInsertPreservesCOW() {
        var rope = TextRope("hello")
        let copy = rope
        rope.insert("X", at: 0)
        XCTAssertEqual(copy.content, "hello")
        XCTAssertEqual(rope.content, "Xhello")
    }

    func testInsertCascadingSplits() {
        let chunkSize = 2048
        let leafCount = 8 * 8
        let bigString = String(repeating: "A", count: chunkSize * leafCount)
        var rope = TextRope(bigString)
        verifyTreeInvariants(rope)
        let insertContent = String(repeating: "Z", count: chunkSize * 2)
        rope.insert(insertContent, at: 0)
        XCTAssertEqual(rope.content, insertContent + bigString)
        XCTAssertEqual(rope.utf8Count, bigString.utf8.count + insertContent.utf8.count)
        verifyTreeInvariants(rope)
    }

    func testInsertUpdatesUTF16Count() {
        var rope = TextRope("abc")
        XCTAssertEqual(rope.utf16Count, 3)
        rope.insert("de", at: 1)
        XCTAssertEqual(rope.utf16Count, 5)
        rope.insert("\u{1F600}", at: 0)
        XCTAssertEqual(rope.utf16Count, 7)
    }

    func testInsertOnSingleOwnerRopeMutatesInPlace() {
        let blocks = (0..<21).map { _ in String(repeating: "x", count: 2000) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(rope.root.children.map(\.children.count), [8, 8, 5])
        let rootBefore = ObjectIdentifier(rope.root)
        let untouchedBefore = ObjectIdentifier(rope.root.children[1])

        rope.insert("Y", at: 41_060)

        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
        XCTAssertEqual(ObjectIdentifier(rope.root.children[1]), untouchedBefore)
    }

    func testInsertOnSharedRopeSharesUnaffectedSubtrees() {
        let blocks = (0..<21).map { _ in String(repeating: "x", count: 2000) }
        let original = TextRope(blocks.joined())
        XCTAssertEqual(original.root.children.map(\.children.count), [8, 8, 5])

        var copy = original
        copy.insert("Y", at: 41_060)

        XCTAssertTrue(copy.root !== original.root, "root must be path-copied")
        XCTAssertTrue(copy.root.children[2] !== original.root.children[2], "subtree on the insert path must be path-copied")

        XCTAssertTrue(copy.root.children[0] === original.root.children[0], "untouched subtree must stay shared")
        XCTAssertTrue(copy.root.children[1] === original.root.children[1], "untouched subtree must stay shared")
        for i in 0..<4 {
            XCTAssertTrue(
                copy.root.children[2].children[i] === original.root.children[2].children[i],
                "untouched sibling leaf \(i) must stay shared"
            )
        }

        XCTAssertEqual(original.content, blocks.joined())
        XCTAssertEqual(copy.utf16Count, original.utf16Count + 1)
    }

    func testInsertAtOffsetInsideSurrogatePairLandsAtScalarBoundary() {
        var rope = TextRope("a😀b")
        rope.insert("X", at: 2)

        XCTAssertEqual(rope.content, "aX😀b")
        XCTAssertEqual(rope.utf16Count, 5)
        XCTAssertEqual(rope.utf8Count, "aX😀b".utf8.count)
    }

    func testInsertBetweenCRAndLFKeepsContentAndLineCountConsistent() {
        var rope = TextRope("first\r\nsecond")
        XCTAssertEqual(rope.root.summary.lines, 1)

        rope.insert("X", at: 6)

        XCTAssertEqual(rope.content, "first\rX\nsecond")
        XCTAssertEqual(rope.root.summary.lines, 1)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(rope.content))
    }

    func testInsertedCRLFIsNotSplitByTheResultingLeafSplit() {
        let base = String(repeating: "a", count: 2000)
        var rope = TextRope(base)
        XCTAssertTrue(rope.root.isLeaf)

        let inserted = String(repeating: "y", count: 49) + "\r\n" + String(repeating: "z", count: 49)
        rope.insert(inserted, at: 1000)

        var expected = base
        expected.insert(contentsOf: inserted, at: expected.index(expected.startIndex, offsetBy: 1000))
        XCTAssertEqual(rope.content, expected)
        XCTAssertFalse(rope.root.isLeaf, "insert must have grown the rope past one leaf")
        verifyTreeInvariants(rope)
    }

    func testInsertPrependingLFToSiblingLeafAfterCRTerminatedLeafDoesNotSplitCRLF() {
        let base = String(repeating: "a", count: 2047) + "\r" + String(repeating: "b", count: 2048)
        var rope = TextRope(base)
        XCTAssertEqual(leafChunks(rope).map(\.utf8.count), [2048, 2048])
        XCTAssertTrue(leafChunks(rope)[0].hasSuffix("\r"))

        rope.insert("\n", at: 2048)

        var expected = base
        expected.insert("\n", at: expected.utf16.index(expected.utf16.startIndex, offsetBy: 2048))
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(expected))
        verifyTreeInvariants(rope, context: "after LF insert at the sibling-leaf boundary")
    }

    func testInsertPrependingLFAcrossSubtreeBoundaryAfterCRTerminatedLeafDoesNotSplitCRLF() {
        let base = String(repeating: "a", count: 5 * 2048 - 1) + "\r" + String(repeating: "b", count: 4 * 2048)
        var rope = TextRope(base)
        XCTAssertEqual(rope.root.children.map(\.children.count), [5, 4])
        XCTAssertTrue(leafChunks(rope)[4].hasSuffix("\r"))
        let original = rope

        rope.insert("\n", at: 5 * 2048)

        var expected = base
        expected.insert("\n", at: expected.utf16.index(expected.utf16.startIndex, offsetBy: 5 * 2048))
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(expected))
        XCTAssertEqual(original.content, base, "seam repair across the subtree boundary must not mutate the shared original")
        verifyTreeInvariants(rope, context: "after LF insert at the subtree boundary")
    }

    private func leafChunks(_ rope: TextRope) -> [String] {
        func collect(_ node: TextRope.Node) -> [String] {
            node.isLeaf ? [node.chunk] : node.children.flatMap(collect)
        }
        return collect(rope.root)
    }

    func testRepeatedInsertionsGrowSingleLeafToThreePlusLevels() {
        var rope = TextRope()
        var oracle = ""
        XCTAssertTrue(rope.root.isLeaf)

        let fragments = ["aé你😀\n", String(repeating: "b", count: 400), "line\r\n你好𝄞"]
        var step = 0
        while Int(rope.root.height) < 3 {
            let fragment = fragments[step % fragments.count]
            let position: Int
            switch step % 3 {
            case 0: position = 0
            case 1: position = TextRopeStressTests.validUTF16Offset(oracle.utf16.count / 2, in: oracle)
            default: position = oracle.utf16.count
            }
            rope.insert(fragment, at: position)
            let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: position)
            oracle.insert(contentsOf: fragment, at: idx)
            step += 1

            // Sampled validation (decided 2026-08-01): per-operation coverage is provided by
            // TextRopeStressTests.testPerOperationInvariantValidation (DEF-007).
            if step % 100 == 0 {
                XCTAssertEqual(rope.content, oracle, "diverged at step \(step)")
                verifyTreeInvariants(rope, context: "step \(step)")
            }
        }

        XCTAssertGreaterThanOrEqual(Int(rope.root.height), 3)
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(oracle))
        verifyTreeInvariants(rope, context: "final")
    }

    func testInsertOnSingleOwnerMultiLevelRopeKeepsOnPathNodeIdentity() {
        let blocks = (0..<20).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(
            rope.root.children.map(\.children.count), [8, 8, 4],
            "test assumes a height-2 tree of 20 full leaves grouped [8, 8, 4]; a chunking or branching change invalidates the on-path indices below"
        )
        // ObjectIdentifier holds no ownership; a node binding would be a second strong
        // reference and defeat the in-place mutation this test asserts (design D2 of
        // fix-rope-cow-and-equality-coverage). Pins rope-insert's single-owner scenario,
        // which was correct on HEAD but untested (design D4).
        let rootBefore = ObjectIdentifier(rope.root)
        let onPathInnerBefore = ObjectIdentifier(rope.root.children[0])
        let onPathLeafBefore = ObjectIdentifier(rope.root.children[0].children[0])

        rope.insert("x", at: 100)

        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
        XCTAssertEqual(
            ObjectIdentifier(rope.root.children[0]), onPathInnerBefore,
            "inner node on the insert path must be mutated in place when the rope has a single owner"
        )
        XCTAssertEqual(
            ObjectIdentifier(rope.root.children[0].children[0]), onPathLeafBefore,
            "leaf on the insert path must be mutated in place when the rope has a single owner"
        )

        var expected = blocks.joined()
        expected.insert("x", at: expected.utf16.index(expected.utf16.startIndex, offsetBy: 100))
        XCTAssertEqual(rope.content, expected)
    }

    func testMultipleInserts() {
        var rope = TextRope("ac")
        rope.insert("b", at: 1)
        XCTAssertEqual(rope.content, "abc")
        rope.insert("d", at: 3)
        XCTAssertEqual(rope.content, "abcd")
        rope.insert("0", at: 0)
        XCTAssertEqual(rope.content, "0abcd")
        rope.insert("X", at: 2)
        XCTAssertEqual(rope.content, "0aXbcd")
    }

    // MARK: - Bulk insert into a non-root leaf (DEF-011, insert half)

    /// 8 full leaves under one inner root, all ASCII, so UTF-16 offsets equal byte
    /// offsets. Offset 5000 sits inside the third leaf (bytes 4096..<6144) — a middle,
    /// non-root leaf.
    private let bulkBase = String(repeating: "a", count: 8 * 2048)
    private let bulkOffset = 5000

    private func expectedSplice(of insert: String, into base: String, at offset: Int) -> String {
        var expected = base
        expected.insert(contentsOf: insert, at: expected.index(expected.startIndex, offsetBy: offset))
        return expected
    }

    /// Asserts invariants and content, never exact chunk boundaries: `chunkLeaves` and
    /// the historical repeated-`splitLeaf` loop pick different split points, and ADR-012
    /// pins bounds, not offsets.
    func testBulkInsertIntoNonRootMiddleLeafPreservesContentAndInvariants() {
        var rope = TextRope(bulkBase)
        XCTAssertFalse(rope.root.isLeaf, "the base must have inner nodes, or this degrades into the root-leaf branch")
        let insert = String((0..<300 * 1024).map { Character(UnicodeScalar(97 + UInt8($0 % 26))) })

        rope.insert(insert, at: bulkOffset)

        XCTAssertEqual(rope.content, expectedSplice(of: insert, into: bulkBase, at: bulkOffset))
        verifyTreeInvariants(rope, context: "300 KiB into a non-root middle leaf")
    }

    func testBulkInsertWithCRLFPairsNearChunkBoundariesKeepsPairsIntact() {
        // A 2049-byte period (2047 fillers + CRLF) drifts the pairs across every
        // position relative to the 2048-byte chunk target, so some land at seams.
        var rope = TextRope(bulkBase)
        let insert = String(repeating: String(repeating: "x", count: 2047) + "\r\n", count: 100)

        rope.insert(insert, at: bulkOffset)

        XCTAssertEqual(rope.content, expectedSplice(of: insert, into: bulkBase, at: bulkOffset))
        XCTAssertEqual(rope.root.summary.lines, 100, "the leaf summaries must sum to the line count of the combined text")
        verifyTreeInvariants(rope, context: "CRLF pairs drifting across chunk boundaries")
    }

    func testBulkInsertOfEmojiDivergesUTF8AndUTF16AcrossEveryLeaf() {
        // U+1F600 is 4 UTF-8 bytes but 2 UTF-16 units, so utf8 and utf16 diverge in
        // every leaf the re-chunk produces.
        var rope = TextRope(bulkBase)
        let insert = String(repeating: "\u{1F600}", count: 50_000)

        rope.insert(insert, at: bulkOffset)

        XCTAssertEqual(rope.content, expectedSplice(of: insert, into: bulkBase, at: bulkOffset))
        XCTAssertEqual(rope.utf8Count, bulkBase.utf8.count + 200_000)
        XCTAssertEqual(rope.utf16Count, bulkBase.utf16.count + 100_000)
        verifyTreeInvariants(rope, context: "200 KiB of 4-byte clusters")
    }

    func testSplicedChunkJustOverMaxSplitsIntoExactlyOneExtraLeaf() {
        // 2048 + 1 = 2049 bytes: the single-extra-leaf case. Exactly two conforming
        // chunks exist for 2049 bytes (three would drop below minChunkUTF8), so the
        // leaf-count assertion follows from the bounds, not from a pinned shape.
        var rope = TextRope(bulkBase)

        rope.insert("X", at: bulkOffset)

        XCTAssertEqual(rope.content, expectedSplice(of: "X", into: bulkBase, at: bulkOffset))
        XCTAssertEqual(leafCount(rope), 9)
        verifyTreeInvariants(rope, context: "spliced chunk of 2049 bytes")
    }

    func testSplicedChunkJustOverMaxPlusMinTakesTheMaxTargetingBranch() {
        // 2048 + 1025 = 3073 bytes: one over maxChunkUTF8 + minChunkUTF8, the point
        // where leadingChunkEnd switches from the balanced-window search to targeting
        // maxChunkUTF8 outright.
        var rope = TextRope(bulkBase)
        let insert = String(repeating: "y", count: 1025)

        rope.insert(insert, at: bulkOffset)

        XCTAssertEqual(rope.content, expectedSplice(of: insert, into: bulkBase, at: bulkOffset))
        verifyTreeInvariants(rope, context: "spliced chunk of 3073 bytes")
    }

    func testMultiMegabyteInsertHandsParentAWideSiblingBatch() {
        // 4 MiB re-chunks into ~2048 leaves delivered to the parent in one batch —
        // far wider than maxChildren (8) — and must cascade through splitInner up to
        // buildTree at the root.
        var rope = TextRope(bulkBase)
        let insert = String(repeating: "z", count: 4 << 20)

        rope.insert(insert, at: bulkOffset)

        XCTAssertEqual(rope.content, expectedSplice(of: insert, into: bulkBase, at: bulkOffset))
        XCTAssertEqual(
            rope.root.summary, TextRope.Summary.of(rope.content),
            "the root summary must equal the summary of the full content after the cascading splits"
        )
        verifyTreeInvariants(rope, context: "4 MiB wide-batch insert")
    }

    /// Optional perf guard (droppable if unstable on CI): a 4× larger insert must cost
    /// less than 8× the time — linear scaling predicts ≈4×, the historical repeated-
    /// `splitLeaf` quadratic ≈16×. Skips below the noise floor per the design's risk note.
    func testBulkInsertCostGrowsLinearlyWithInsertedLength() throws {
        let clock = ContinuousClock()
        func measuredInsert(bytes: Int) -> Duration {
            let insert = String(repeating: "z", count: bytes)
            var best = Duration.seconds(1000)
            for _ in 0..<3 {
                var rope = TextRope(bulkBase)
                let elapsed = clock.measure { rope.insert(insert, at: bulkOffset) }
                best = min(best, elapsed)
            }
            return best
        }
        _ = measuredInsert(bytes: 1 << 20) // warm-up

        let small = measuredInsert(bytes: 1 << 20)
        let large = measuredInsert(bytes: 4 << 20)

        try XCTSkipIf(small < .milliseconds(2), "1 MiB baseline (\(small)) is below the noise floor; the ratio would be meaningless")
        XCTAssertLessThan(large / small, 8.0, "4 MiB took \(large) vs \(small) for 1 MiB — quadratic scaling would be ≈16×, linear ≈4×")
    }

    private func leafCount(_ rope: TextRope) -> Int {
        func count(_ node: TextRope.Node) -> Int {
            node.isLeaf ? 1 : node.children.reduce(0) { $0 + count($1) }
        }
        return count(rope.root)
    }
}

@Suite struct TextRopeInsertPreconditions {
    @Test func `inserting traps for an offset past the end`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.insert("x", at: 500)
        }
    }

    @Test func `inserting an empty string traps for an offset past the end`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.insert("", at: 500)
        }
    }

    @Test func `inserting an empty string traps for a negative offset`() async {
        await #expect(processExitsWith: .failure) {
            var rope = TextRope("hello")
            rope.insert("", at: -1)
        }
    }
}
