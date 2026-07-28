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

    func testLeafSplitPointSplitsOversizedChunkAtMidpoint() {
        let chunk = String(repeating: "a", count: 2049)
        let split = TextRope.Node.leafSplitPoint(in: chunk[...])
        XCTAssertEqual(chunk.utf8.distance(from: chunk.utf8.startIndex, to: split), 1025)
    }

    func testLeafSplitPointCapsAtMaxChunkForHugeChunks() {
        let chunk = String(repeating: "a", count: 10_000)
        let split = TextRope.Node.leafSplitPoint(in: chunk[...])
        XCTAssertEqual(chunk.utf8.distance(from: chunk.utf8.startIndex, to: split), TextRope.Node.maxChunkUTF8)
    }

    func testSplitLeafProducesBothHalvesAboveMinimum() {
        let node = TextRope.Node.leaf(String(repeating: "a", count: 2049))
        let sibling = node.splitLeaf()
        XCTAssertEqual(node.chunk.utf8.count, 1025)
        XCTAssertEqual(sibling.chunk.utf8.count, 1024)
        XCTAssertEqual(node.summary, TextRope.Summary.of(node.chunk))
        XCTAssertEqual(sibling.summary, TextRope.Summary.of(sibling.chunk))
    }

    func testLeafSplitPointDoesNotSplitCRLFAtMidpoint() {
        let chunk = String(repeating: "a", count: 1024) + "\r\n" + String(repeating: "b", count: 1023)
        let split = TextRope.Node.leafSplitPoint(in: chunk[...])
        XCTAssertEqual(chunk.utf8.distance(from: chunk.utf8.startIndex, to: split), 1024)
        XCTAssertFalse(String(chunk[chunk.startIndex..<split]).hasSuffix("\r"))
    }

    func testLeafSplitPointAdjustsWhenMidpointLandsInsideMultiByteCharacter() {
        let chunk = String(repeating: "a", count: 1023) + "\u{1F600}" + String(repeating: "b", count: 1022)
        XCTAssertEqual(chunk.utf8.count, 2049)
        let split = TextRope.Node.leafSplitPoint(in: chunk[...])
        XCTAssertEqual(chunk.utf8.distance(from: chunk.utf8.startIndex, to: split), 1023)
        XCTAssertEqual(String(chunk[chunk.startIndex..<split]) + String(chunk[split...]), chunk)
    }

    func testLeafSplitPointOnChunkOfOnlyMultiByteCharacters() {
        let chunk = String(repeating: "\u{1F600}", count: 513)
        XCTAssertEqual(chunk.utf8.count, 2052)
        let split = TextRope.Node.leafSplitPoint(in: chunk[...])
        XCTAssertEqual(chunk.utf8.distance(from: chunk.utf8.startIndex, to: split), 1024)
        XCTAssertEqual(String(chunk[chunk.startIndex..<split]) + String(chunk[split...]), chunk)
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
