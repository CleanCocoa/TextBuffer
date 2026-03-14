import XCTest
@testable import TextRope

final class TextRopeConstructionTests: XCTestCase {
    func testEmptyString() {
        let rope = TextRope("")
        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.content, "")
    }

    func testShortASCII() {
        let rope = TextRope("hello")
        XCTAssertEqual(rope.content, "hello")
    }

    func testMultiByteCharacters() {
        let input = "Hello 😀 World"
        let rope = TextRope(input)
        XCTAssertEqual(rope.content, input)
    }

    func testSurrogatePairs() {
        let input = "𝄞"
        let rope = TextRope(input)
        XCTAssertEqual(rope.content, input)
        XCTAssertEqual(rope.utf16Count, input.utf16.count)
    }

    func testCRLFNotSplit() {
        let prefix = String(repeating: "a", count: 2047)
        let input = prefix + "\r\n" + "b"
        let rope = TextRope(input)
        XCTAssertEqual(rope.content, input)

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
                "Chunk ends with bare \\r, meaning \\r\\n was split"
            )
        }
    }

    func testLargeString() {
        let input = String(repeating: "x", count: 5000)
        let rope = TextRope(input)
        XCTAssertEqual(rope.content, input)
        XCTAssertEqual(rope.utf16Count, input.utf16.count)
    }

    func testSingleCharacter() {
        let rope = TextRope("a")
        XCTAssertEqual(rope.content, "a")
    }

    func testOnlyNewlines() {
        let input = "\n\n\n"
        let rope = TextRope(input)
        XCTAssertEqual(rope.content, input)
    }

    func testUTF16CountMatchesString() {
        let strings = [
            "",
            "hello",
            "Hello 😀 World",
            "𝄞",
            "\r\n\r\n",
            String(repeating: "é", count: 3000),
        ]
        for string in strings {
            let rope = TextRope(string)
            XCTAssertEqual(
                rope.utf16Count, string.utf16.count,
                "UTF-16 count mismatch for: \(string.prefix(20))..."
            )
        }
    }
}
