import XCTest
@testable import TextRope

final class TextRopeEqualityTests: XCTestCase {
    /// 6000 bytes of cycling ASCII letters — larger than `Node.maxChunkUTF8` (2048), so
    /// comparisons over this content are never the single-leaf trivial case.
    private let multiLeafContent = String((0..<6000).map { Character(UnicodeScalar(97 + UInt8($0 % 26))) })

    private func leafChunkLengths(_ rope: TextRope) -> [Int] {
        func collect(_ node: TextRope.Node) -> [Int] {
            node.isLeaf ? [node.chunk.utf8.count] : node.children.flatMap(collect)
        }
        return collect(rope.root)
    }

    func testRopesWithSameContentAreEqual() {
        let a = TextRope(multiLeafContent)
        let b = TextRope(multiLeafContent)

        XCTAssertTrue(a.root !== b.root, "independent constructions must not share a root, or this degrades into the identity fast path")
        XCTAssertEqual(a, b)
    }

    func testEmptyRopesAreEqual() {
        XCTAssertEqual(TextRope(), TextRope(""))
    }

    func testRopesWithSameContentButDifferentTreeShapesAreEqual() {
        let oneShot = TextRope(multiLeafContent)

        var incremental = TextRope(String(multiLeafContent.prefix(1500)))
        var offset = 1500
        while offset < multiLeafContent.count {
            let slice = multiLeafContent.dropFirst(offset).prefix(700)
            incremental.insert(String(slice), at: offset)
            offset += slice.count
        }

        XCTAssertEqual(incremental.content, multiLeafContent, "incremental construction must reproduce the content exactly")
        XCTAssertNotEqual(
            leafChunkLengths(oneShot), leafChunkLengths(incremental),
            "the two ropes must hold the same content over different leaf partitions, or this test degrades into testRopesWithSameContentAreEqual"
        )
        XCTAssertEqual(oneShot, incremental)
        XCTAssertEqual(incremental, oneShot)
    }

    func testRopesWithDifferentContentAreNotEqual() {
        XCTAssertNotEqual(TextRope("hello world"), TextRope("hello swirl"))
        XCTAssertNotEqual(TextRope(multiLeafContent), TextRope(multiLeafContent + "!"))
    }

    func testRopesWithSameUTF16CountButDifferentContentAreNotEqual() {
        let prefix = String(repeating: "x", count: 3000) + "\n"
        let suffix = "\n" + String(repeating: "y", count: 3000)
        let a = TextRope(prefix + "AB" + suffix)
        let b = TextRope(prefix + "BA" + suffix)

        XCTAssertEqual(
            a.root.summary, b.root.summary,
            "the contents are chosen so utf8, utf16, and line counts all match — a summary-based early-out (DEF-010) must not be able to satisfy this test"
        )
        XCTAssertNotEqual(a, b)
    }

    // MARK: - Summary early-out guards (DEF-010)

    /// Returns the index of the leaf whose chunk contains the byte at `utf8Offset`.
    private func leafIndex(containing utf8Offset: Int, in rope: TextRope) -> Int {
        var remaining = utf8Offset
        for (index, length) in leafChunkLengths(rope).enumerated() {
            if remaining < length { return index }
            remaining -= length
        }
        XCTFail("offset \(utf8Offset) beyond rope content")
        return -1
    }

    func testMultiLeafRopesWithPermutedBytesAcrossLeafBoundariesAreNotEqual() {
        // 6000 bytes with 'A' at offset 100 and 'B' at offset 5000 — the differing bytes
        // land in different leaves, so no per-leaf comparison shortcut could decide this
        // either. All three summary fields match: same bytes, permuted.
        func content(first: String, second: String) -> String {
            String(repeating: "x", count: 100) + first
                + String(repeating: "x", count: 4899) + second
                + String(repeating: "x", count: 999)
        }
        let a = TextRope(content(first: "A", second: "B"))
        let b = TextRope(content(first: "B", second: "A"))

        XCTAssertEqual(
            a.root.summary, b.root.summary,
            "permuting bytes must not change utf8, utf16, or line counts — the summary early-out cannot decide this pair"
        )
        XCTAssertNotEqual(
            leafIndex(containing: 100, in: a), leafIndex(containing: 5000, in: a),
            "the differing bytes must sit in different leaves, or this degrades into the single-leaf permutation case"
        )
        XCTAssertNotEqual(a, b)
    }

    func testCopyMutatedThenRestoredComparesEqualAgain() {
        let original = TextRope(multiLeafContent)
        var copy = original

        copy.insert("intruder", at: 2000)
        XCTAssertNotEqual(original, copy)

        copy.delete(in: 2000..<2008)
        XCTAssertTrue(original.root !== copy.root, "mutation must have unshared the roots, or equality degrades into the identity fast path")
        XCTAssertEqual(original.content, copy.content, "the mutation sequence must restore the original text exactly")
        XCTAssertEqual(original, copy)
        XCTAssertEqual(copy, original)
    }

    func testRopesWithSameUTF16CountButDifferentUTF8CountAreNotEqual() {
        // "é" is one UTF-16 code unit but two UTF-8 bytes, so "éa" and "aa" share a
        // UTF-16 count of 2 while their byte counts differ (3 vs 2).
        let a = TextRope("éa" + multiLeafContent)
        let b = TextRope("aa" + multiLeafContent)

        XCTAssertEqual(a.root.summary.utf16, b.root.summary.utf16)
        XCTAssertEqual(a.root.summary.lines, b.root.summary.lines)
        XCTAssertNotEqual(a.root.summary.utf8, b.root.summary.utf8, "the fixture must differ in UTF-8 count so the summary alone decides it")
        XCTAssertNotEqual(a, b)
    }

    func testRopesWithSameByteCountsButDifferentLineCountsAreNotEqual() {
        let a = TextRope(multiLeafContent + "a\nb")
        let b = TextRope(multiLeafContent + "abc")

        XCTAssertEqual(a.root.summary.utf8, b.root.summary.utf8)
        XCTAssertEqual(a.root.summary.utf16, b.root.summary.utf16)
        XCTAssertNotEqual(a.root.summary.lines, b.root.summary.lines, "the fixture must differ only in line count so the summary alone decides it")
        XCTAssertNotEqual(a, b)
    }

    func testCopyWithSharedRootIsEqual() {
        let a = TextRope(multiLeafContent)
        let b = a

        XCTAssertTrue(a.root === b.root, "an unmutated copy must share its root, the precondition of the identity fast path")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, a)
    }
}
