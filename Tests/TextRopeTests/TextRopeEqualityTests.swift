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

    func testCopyWithSharedRootIsEqual() {
        let a = TextRope(multiLeafContent)
        let b = a

        XCTAssertTrue(a.root === b.root, "an unmutated copy must share its root, the precondition of the identity fast path")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a, a)
    }
}
