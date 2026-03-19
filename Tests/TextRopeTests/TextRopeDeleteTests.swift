import XCTest
import Foundation
@testable import TextRope

final class TextRopeDeleteTests: XCTestCase {
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

        let deleteLen = 800
        rope.delete(in: NSRange(location: a.utf16.count - deleteLen / 2, length: deleteLen))

        let expectedA = String(a.prefix(a.count - deleteLen / 2))
        let expectedB = String(b.dropFirst(deleteLen / 2))
        let expected = expectedA + expectedB
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.utf16Count, expected.utf16.count)
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
