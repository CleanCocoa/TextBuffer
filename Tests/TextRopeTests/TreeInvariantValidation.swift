import XCTest
@testable import TextRope

func verifyTreeInvariants(_ rope: TextRope, context: String = "", file: StaticString = #filePath, line: UInt = #line) {
    let prefix = context.isEmpty ? "" : "\(context): "
    let root = rope.root
    verifyConsistentLeafDepth(root, prefix: prefix, file: file, line: line)
    verifyChildCounts(root, isRoot: true, prefix: prefix, file: file, line: line)
    verifyChunkSizes(root, prefix: prefix, file: file, line: line)
    verifyCRLFNotSplitAcrossLeaves(root, prefix: prefix, file: file, line: line)
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
    if root.isLeaf { return }
    let leaves = collectLeaves(root)
    for (index, leaf) in leaves.enumerated() {
        let size = leaf.chunk.utf8.count
        XCTAssertLessThanOrEqual(size, TextRope.Node.maxChunkUTF8, "\(prefix)Leaf \(index) has \(size) UTF-8 bytes, max is \(TextRope.Node.maxChunkUTF8)", file: file, line: line)
        XCTAssertGreaterThanOrEqual(size, TextRope.Node.minChunkUTF8, "\(prefix)Leaf \(index) has \(size) UTF-8 bytes, min is \(TextRope.Node.minChunkUTF8)", file: file, line: line)
    }
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
