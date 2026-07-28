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
        XCTAssertEqual(leafChunkSizes(rope), [1051, 1049])
        XCTAssertTrue(rope.root.children[0].chunk.hasSuffix("\r\n"))
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
}
