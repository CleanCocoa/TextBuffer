import XCTest
@testable import TextRope

final class NodeTests: XCTestCase {
    func testEmptyLeaf() {
        let node = TextRope.Node.emptyLeaf()
        XCTAssertTrue(node.isLeaf)
        XCTAssertEqual(node.height, 0)
        XCTAssertEqual(node.chunk, "")
        XCTAssertTrue(node.children.isEmpty)
        XCTAssertEqual(node.summary, TextRope.Summary.zero)
    }

    func testLeaf() {
        let node = TextRope.Node.leaf("hello")
        XCTAssertTrue(node.isLeaf)
        XCTAssertEqual(node.height, 0)
        XCTAssertEqual(node.chunk, "hello")
        XCTAssertEqual(node.summary.utf8, 5)
        XCTAssertEqual(node.summary.utf16, 5)
    }

    func testInnerNode() {
        let a = TextRope.Node.leaf("abc")
        let b = TextRope.Node.leaf("de")
        let inner = TextRope.Node.inner([a, b])
        XCTAssertFalse(inner.isLeaf)
        XCTAssertEqual(inner.height, 1)
        XCTAssertEqual(inner.summary.utf8, 5)
        XCTAssertEqual(inner.summary.utf16, 5)
        XCTAssertEqual(inner.children.count, 2)
    }

    func testShallowCopyProducesIndependentNode() {
        let original = TextRope.Node.leaf("hello")
        let copy = original.shallowCopy()
        copy.chunk = "world"
        copy.summary = TextRope.Summary.of("world")
        XCTAssertEqual(original.chunk, "hello")
        XCTAssertEqual(copy.chunk, "world")
    }

    func testShallowCopyOfInnerSharesChildren() {
        let child = TextRope.Node.leaf("abc")
        let inner = TextRope.Node.inner([child])
        let copy = inner.shallowCopy()
        XCTAssertTrue(copy.children[0] === child)
    }
}
