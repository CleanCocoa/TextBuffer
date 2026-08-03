import XCTest
import Foundation
@testable import TextRope

final class TextRopeDeleteTests: XCTestCase {
    private func leafChunkSizes(_ rope: TextRope) -> [Int] {
        func collect(_ node: TextRope.Node) -> [Int] {
            node.isLeaf ? [node.chunk.utf8.count] : node.children.flatMap(collect)
        }
        return collect(rope.root)
    }

    func testDeleteFromStart() {
        var rope = TextRope("hello world")
        rope.delete(in: NSRange(location: 0, length: 3))
        XCTAssertEqual(rope.content, "lo world")
    }

    func testDeleteFromEnd() {
        var rope = TextRope("hello world")
        let len = "hello world".utf16.count
        rope.delete(in: NSRange(location: len - 3, length: 3))
        XCTAssertEqual(rope.content, "hello wo")
    }

    func testDeleteFromMiddle() {
        var rope = TextRope("hello world")
        rope.delete(in: NSRange(location: 3, length: 5))
        XCTAssertEqual(rope.content, "helrld")
    }

    func testDeleteEmptyRange() {
        var rope = TextRope("hello world")
        rope.delete(in: NSRange(location: 3, length: 0))
        XCTAssertEqual(rope.content, "hello world")
    }

    func testDeleteAll() {
        var rope = TextRope("hello world")
        rope.delete(in: NSRange(location: 0, length: "hello world".utf16.count))
        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.content, "")
        XCTAssertEqual(rope.utf16Count, 0)
        XCTAssertEqual(rope.utf8Count, 0)
        XCTAssertTrue(rope.root.isLeaf)
    }

    func testDeleteAllFromTwoLeafRope() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 1200)
        var rope = TextRope(a + b)
        XCTAssertEqual(leafChunkSizes(rope), [1200, 1200])

        rope.delete(in: NSRange(location: 0, length: 2400))

        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.content, "")
        XCTAssertEqual(rope.utf16Count, 0)
        XCTAssertEqual(rope.utf8Count, 0)
        XCTAssertTrue(rope.root.isLeaf)
        verifyTreeInvariants(rope)
    }

    func testDeleteAllFromMultiLevelRope() {
        let blocks = (0..<24).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(Int(rope.root.height), 2)

        rope.delete(in: NSRange(location: 0, length: rope.utf16Count))

        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.content, "")
        XCTAssertEqual(rope.utf16Count, 0)
        XCTAssertEqual(rope.utf8Count, 0)
        XCTAssertTrue(rope.root.isLeaf)
        verifyTreeInvariants(rope)
    }

    func testDeleteAlmostEverythingCollapsesRootRepeatedlyToSingleLeaf() {
        let blocks = (0..<24).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(Int(rope.root.height), 2)

        rope.delete(in: NSRange(location: 100, length: rope.utf16Count - 100))

        XCTAssertEqual(rope.content, String(blocks[0].prefix(100)))
        XCTAssertTrue(rope.root.isLeaf)
        XCTAssertEqual(rope.utf16Count, 100)
        verifyTreeInvariants(rope)
    }

    func testDeleteAllThenInsertFunctionsCorrectly() {
        let blocks = (0..<24).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2048) }
        var rope = TextRope(blocks.joined())

        rope.delete(in: NSRange(location: 0, length: rope.utf16Count))
        rope.insert("new", at: 0)

        XCTAssertEqual(rope.content, "new")
        XCTAssertEqual(rope.utf16Count, 3)
        XCTAssertFalse(rope.isEmpty)

        rope.insert(" content", at: 3)
        XCTAssertEqual(rope.content, "new content")
        verifyTreeInvariants(rope)
    }

    func testDeleteSpanningLeaves() {
        let chunk = String(repeating: "a", count: 1500)
        let input = chunk + "BBBB" + chunk
        var rope = TextRope(input)
        let expected = chunk + chunk

        let deleteStart = chunk.utf16.count
        rope.delete(in: NSRange(location: deleteStart, length: 4))
        XCTAssertEqual(rope.content, expected)
    }

    func testDeleteCausingLeafMerge() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 1200)
        let input = a + b
        var rope = TextRope(input)

        rope.delete(in: NSRange(location: 900, length: 300))

        let expected = String(a.prefix(900)) + b
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.utf16Count, expected.utf16.count)
        XCTAssertEqual(leafChunkSizes(rope).count, 2)
        XCTAssertEqual(leafChunkSizes(rope).reduce(0, +), 2100)
        verifyTreeInvariants(rope)
    }

    func testDeleteMergingAdjacentUndersizedLeaves() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 1200)
        let input = a + b
        var rope = TextRope(input)

        let deleteLen = 800
        rope.delete(in: NSRange(location: a.utf16.count - deleteLen / 2, length: deleteLen))

        let expectedA = String(a.prefix(a.count - deleteLen / 2))
        let expectedB = String(b.dropFirst(deleteLen / 2))
        let expected = expectedA + expectedB
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.utf16Count, expected.utf16.count)
        XCTAssertTrue(rope.root.isLeaf)
        XCTAssertEqual(rope.root.chunk.utf8.count, 1600)
        verifyTreeInvariants(rope)
    }

    func testDeleteSpanningMiddleLeavesMergesBothUndersizedEdges() {
        let blocks = ["a", "b", "c", "d"].map { String(repeating: $0, count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2048, 2048, 2048])

        rope.delete(in: NSRange(location: 900, length: 6392))

        let expected = String(blocks[0].prefix(900)) + String(blocks[3].suffix(900))
        XCTAssertEqual(rope.content, expected)
        XCTAssertTrue(rope.root.isLeaf)
        XCTAssertEqual(rope.root.chunk.utf8.count, 1800)
        verifyTreeInvariants(rope)
    }

    func testDeleteMakingLastLeafUndersizedAbsorbsLeftward() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 1200)
        var rope = TextRope(a + b)
        XCTAssertEqual(leafChunkSizes(rope), [1200, 1200])

        rope.delete(in: NSRange(location: 1800, length: 600))

        let expected = a + String(b.prefix(600))
        XCTAssertEqual(rope.content, expected)
        XCTAssertTrue(rope.root.isLeaf)
        XCTAssertEqual(rope.root.chunk.utf8.count, 1800)
        verifyTreeInvariants(rope)
    }

    func testDeleteMakingLastLeafUndersizedRedistributesLeftward() {
        let a = String(repeating: "a", count: 2048)
        let b = String(repeating: "b", count: 2000)
        var rope = TextRope(a + b)
        XCTAssertEqual(leafChunkSizes(rope), [2048, 2000])

        rope.delete(in: NSRange(location: 2148, length: 1900))

        let expected = a + String(b.prefix(100))
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(leafChunkSizes(rope), [1074, 1074])
        verifyTreeInvariants(rope)
    }

    func testDeleteRedistributionDoesNotSplitCRLFAtTheBalancedSplitPoint() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 149) + "\r\n" + String(repeating: "c", count: 1049)
        var rope = TextRope(a + b)
        XCTAssertEqual(leafChunkSizes(rope), [1200, 1200])

        rope.delete(in: NSRange(location: 900, length: 300))

        XCTAssertEqual(rope.content, String(a.prefix(900)) + b)
        // The redistribution target 1050 is the CR/LF interior; the boundaries 1049 and 1051
        // are equidistant and ties resolve to the lower offset (design D1/ADR-012), so the
        // CRLF pair stays intact at the head of the right leaf. (Before the DEF-001 fix the
        // alternating search happened to check the upper candidate first: [1051, 1049].)
        XCTAssertEqual(leafChunkSizes(rope), [1049, 1051])
        XCTAssertTrue(rope.root.children[1].chunk.hasPrefix("\r\n"))
        verifyTreeInvariants(rope)
    }

    func testDeleteRedistributionRespectsMultiByteBoundariesAtTheBalancedSplitPoint() {
        let a = String(repeating: "a", count: 1200)
        let b = String(repeating: "b", count: 148) + "\u{1F600}" + String(repeating: "c", count: 1048)
        var rope = TextRope(a + b)
        XCTAssertEqual(leafChunkSizes(rope), [1200, 1200])

        rope.delete(in: NSRange(location: 900, length: 300))

        XCTAssertEqual(rope.content, String(a.prefix(900)) + b)
        XCTAssertEqual(leafChunkSizes(rope).count, 2)
        verifyTreeInvariants(rope)
    }

    func testDeleteCollapsingInnerNodeMergesWithSibling() {
        let letters = "abcdefghijklmnopqrst"
        let blocks = letters.map { String(repeating: $0, count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(leafChunkSizes(rope).count, 20)
        XCTAssertEqual(rope.root.children.map(\.children.count), [8, 8, 4])

        rope.delete(in: NSRange(location: 10 * 2048, length: 6 * 2048))

        let expected = blocks[0..<10].joined() + blocks[16...].joined()
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.root.children.map(\.children.count), [8, 6])
        verifyTreeInvariants(rope)
    }

    func testDeleteCollapsingInnerNodeRedistributesWithFullSibling() {
        let blocks = (0..<24).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(rope.root.children.map(\.children.count), [8, 8, 8])

        rope.delete(in: NSRange(location: 10 * 2048, length: 6 * 2048))

        let expected = blocks[0..<10].joined() + blocks[16...].joined()
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.root.children.map(\.children.count), [8, 5, 5])
        verifyTreeInvariants(rope)
    }

    func testDeleteCollapsingLastInnerNodeAbsorbsLeftward() {
        let blocks = (0..<9).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(rope.root.children.map(\.children.count), [5, 4])

        rope.delete(in: NSRange(location: 7 * 2048, length: 2 * 2048))

        XCTAssertEqual(rope.content, blocks[0..<7].joined())
        XCTAssertEqual(Int(rope.root.height), 1)
        XCTAssertEqual(rope.root.children.count, 7)
        verifyTreeInvariants(rope)
    }

    func testDeleteCascadesMergesAcrossMultipleLevels() {
        let blocks = (0..<72).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(Int(rope.root.height), 3)
        XCTAssertEqual(rope.root.children.map(\.children.count), [5, 4])

        rope.delete(in: NSRange(location: 2048, length: 38 * 2048))

        let expected = blocks[0] + blocks[39] + blocks[40...].joined()
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(Int(rope.root.height), 2)
        XCTAssertEqual(rope.root.children.map(\.children.count), [5, 5, 8, 8, 8])
        verifyTreeInvariants(rope)
    }

    func testDeletePreservesCOW() {
        var original = TextRope("hello world")
        let copy = original
        original.delete(in: NSRange(location: 0, length: 5))
        XCTAssertEqual(original.content, " world")
        XCTAssertEqual(copy.content, "hello world")
    }

    func testDeleteUpdatesUTF16Count() {
        var rope = TextRope("hello world")
        let originalCount = rope.utf16Count
        rope.delete(in: NSRange(location: 2, length: 4))
        XCTAssertEqual(rope.utf16Count, originalCount - 4)
        XCTAssertEqual(rope.utf16Count, rope.content.utf16.count)
    }

    func testDeleteMultiByte() {
        let input = "AB\u{1F600}CD"
        var rope = TextRope(input)
        let emojiStart = 2
        let emojiUTF16Len = 2
        rope.delete(in: NSRange(location: emojiStart, length: emojiUTF16Len))
        XCTAssertEqual(rope.content, "ABCD")
        XCTAssertEqual(rope.utf16Count, 4)
    }

    func testDeleteLeafMergeDoesNotSplitCRLF() {
        let beforeCR = String(repeating: "a", count: 2047)
        let afterLF = String(repeating: "b", count: 1500)
        let filler = String(repeating: "c", count: 100)
        let input = beforeCR + "\r\n" + filler + afterLF
        var rope = TextRope(input)

        XCTAssertEqual(rope.content, input)

        let deleteStart = (beforeCR + "\r\n").utf16.count
        rope.delete(in: NSRange(location: deleteStart, length: filler.utf16.count))

        let expected = beforeCR + "\r\n" + afterLF
        XCTAssertEqual(rope.content, expected)

        var chunks: [String] = []
        func collectChunks(_ node: TextRope.Node) {
            if node.isLeaf {
                chunks.append(node.chunk)
            } else {
                for child in node.children {
                    collectChunks(child)
                }
            }
        }
        collectChunks(rope.root)

        for chunk in chunks {
            XCTAssertFalse(
                chunk.hasSuffix("\r") && !chunk.hasSuffix("\r\n"),
                "Chunk ends with bare \\r, meaning \\r\\n was split: chunk has \(chunk.utf8.count) bytes"
            )
        }

        verifyTreeInvariants(rope)
    }

    private func assertSummaryMatchesContent(_ rope: TextRope, _ step: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(rope.content), step, file: file, line: line)
        verifyTreeInvariants(rope, context: step, file: file, line: line)
    }

    func testSummaryStaysCorrectAfterSimpleDelete() {
        var rope = TextRope("hello wonderful world")
        rope.delete(in: NSRange(location: 5, length: 10))
        XCTAssertEqual(rope.content, "hello world")
        assertSummaryMatchesContent(rope, "simple ASCII delete")
    }

    func testSummaryStaysCorrectAfterDeletingMultiByteCharacters() {
        var rope = TextRope("aé你😀𝄞b")
        rope.delete(in: NSRange(location: 2, length: 5))
        XCTAssertEqual(rope.content, "aéb")
        assertSummaryMatchesContent(rope, "multi-byte delete")
    }

    func testSummaryStaysCorrectAfterDeletingNewlines() {
        var rope = TextRope("one\ntwo\r\nthree\nfour")
        XCTAssertEqual(rope.root.summary.lines, 3)

        rope.delete(in: NSRange(location: 3, length: 6))
        XCTAssertEqual(rope.content, "onethree\nfour")
        XCTAssertEqual(rope.root.summary.lines, 1)
        assertSummaryMatchesContent(rope, "newline delete")
    }

    func testSummaryStaysCorrectAfterMultiLevelCascadingMerges() {
        let blocks = (0..<72).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2047) + "\n" }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(Int(rope.root.height), 3)

        rope.delete(in: NSRange(location: 2048, length: 38 * 2048))

        XCTAssertEqual(rope.content, blocks[0] + blocks[39...].joined())
        XCTAssertEqual(Int(rope.root.height), 2)
        assertSummaryMatchesContent(rope, "cascading merges")
    }

    func testDeleteOnCopyLeavesOriginalUnchanged() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        let original = TextRope(blocks.joined())
        let originalContent = original.content

        var copy = original
        copy.delete(in: NSRange(location: 1000, length: 3000))

        XCTAssertEqual(original.content, originalContent)
        XCTAssertNotEqual(copy.content, originalContent)
    }

    func testDeleteOnSingleOwnerRopeMutatesInPlace() {
        let blocks = (0..<4).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        let rootBefore = ObjectIdentifier(rope.root)
        let untouchedLeafBefore = ObjectIdentifier(rope.root.children[2])

        rope.delete(in: NSRange(location: 100, length: 10))

        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
        XCTAssertEqual(ObjectIdentifier(rope.root.children[2]), untouchedLeafBefore)
    }

    func testDeleteOnSharedRopeSharesUnaffectedSubtrees() {
        let blocks = (0..<20).map { String(repeating: Character(UnicodeScalar(97 + $0)!), count: 2048) }
        let original = TextRope(blocks.joined())
        XCTAssertEqual(original.root.children.map(\.children.count), [8, 8, 4])

        var copy = original
        copy.delete(in: NSRange(location: 100, length: 10))

        XCTAssertTrue(copy.root !== original.root, "root must be path-copied")
        XCTAssertTrue(copy.root.children[0] !== original.root.children[0], "subtree on the delete path must be path-copied")
        XCTAssertTrue(copy.root.children[0].children[0] !== original.root.children[0].children[0], "edited leaf must be path-copied")

        XCTAssertTrue(copy.root.children[1] === original.root.children[1], "untouched subtree must stay shared")
        XCTAssertTrue(copy.root.children[2] === original.root.children[2], "untouched subtree must stay shared")
        for i in 1..<8 {
            XCTAssertTrue(
                copy.root.children[0].children[i] === original.root.children[0].children[i],
                "untouched sibling leaf \(i) must stay shared"
            )
        }

        XCTAssertEqual(original.content, blocks.joined())
    }

    func testRepeatedDeletionsShrinkThreeLevelTreeToSingleLeaf() {
        let blocks = (0..<72).map { String(repeating: Character(UnicodeScalar(97 + $0 % 26)!), count: 2048) }
        var rope = TextRope(blocks.joined())
        var oracle = blocks.joined()
        XCTAssertEqual(Int(rope.root.height), 3)

        while oracle.utf16.count > 500 {
            let length = min(5000, oracle.utf16.count - 500)
            let location = (oracle.utf16.count - length) / 2
            rope.delete(in: NSRange(location: location, length: length))

            let startIdx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: location)
            let endIdx = oracle.utf16.index(startIdx, offsetBy: length)
            oracle.removeSubrange(startIdx..<endIdx)

            XCTAssertEqual(rope.content, oracle)
            verifyTreeInvariants(rope, context: "\(oracle.utf16.count) units remaining")
        }

        XCTAssertTrue(rope.root.isLeaf)
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(oracle))
    }

    func testDeleteLeavingCRAndLFOnAdjacentWellSizedLeavesRejoinsThePair() {
        let a = String(repeating: "a", count: 1500)
        let middle = String(repeating: "m", count: 600)
        let b = String(repeating: "b", count: 1500)
        var rope = TextRope(a + "\r" + middle + "\n" + b)
        XCTAssertEqual(leafChunkSizes(rope), [2048, 1554])

        rope.delete(in: NSRange(location: 1501, length: 600))

        XCTAssertEqual(rope.content, a + "\r\n" + b)
        XCTAssertEqual(rope.root.summary.lines, 1)
        verifyTreeInvariants(rope)
    }

    func testDeleteLeavingCRAndLFOnLeavesInDifferentSubtreesRejoinsThePair() {
        var bytes = Array(repeating: Character("a"), count: 20 * 2048)
        bytes[15883] = "\r"
        bytes[16884] = "\n"
        let input = String(bytes)
        var rope = TextRope(input)
        XCTAssertEqual(rope.root.children.map(\.children.count), [8, 8, 4])

        rope.delete(in: NSRange(location: 15884, length: 1000))

        let expected = (input as NSString).replacingCharacters(
            in: NSRange(location: 15884, length: 1000), with: ""
        )
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.root.summary.lines, 1)
        verifyTreeInvariants(rope)
    }
}
