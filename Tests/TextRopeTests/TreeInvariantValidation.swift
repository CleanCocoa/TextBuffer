import XCTest
@testable import TextRope

func verifyTreeInvariants(_ rope: TextRope, file: StaticString = #filePath, line: UInt = #line) {
    let root = rope.root
    verifyConsistentLeafDepth(root, file: file, line: line)
    verifyChildCounts(root, isRoot: true, file: file, line: line)
    verifyChunkSizes(root, file: file, line: line)
    verifySummaries(root, file: file, line: line)
    verifyHeight(root, file: file, line: line)
}

private func verifyConsistentLeafDepth(_ root: TextRope.Node, file: StaticString, line: UInt) {
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
    XCTAssertEqual(unique.count, 1, "Leaves at inconsistent depths: \(leafDepths)", file: file, line: line)
}

private func verifyChildCounts(_ node: TextRope.Node, isRoot: Bool, file: StaticString, line: UInt) {
    guard !node.isLeaf else { return }
    let count = node.children.count
    XCTAssertLessThanOrEqual(count, TextRope.Node.maxChildren, "Inner node has \(count) children, max is \(TextRope.Node.maxChildren)", file: file, line: line)
    if !isRoot {
        XCTAssertGreaterThanOrEqual(count, TextRope.Node.minChildren, "Non-root inner node has \(count) children, min is \(TextRope.Node.minChildren)", file: file, line: line)
    }
    for child in node.children {
        verifyChildCounts(child, isRoot: false, file: file, line: line)
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

private func verifyChunkSizes(_ root: TextRope.Node, file: StaticString, line: UInt) {
    let leaves = collectLeaves(root)
    if leaves.count <= 1 { return }
    for (index, leaf) in leaves.enumerated() {
        let size = leaf.chunk.utf8.count
        XCTAssertLessThanOrEqual(size, TextRope.Node.maxChunkUTF8 + 1, "Leaf chunk has \(size) UTF-8 bytes, max is \(TextRope.Node.maxChunkUTF8) (+ 1 for CRLF)", file: file, line: line)
        let isLast = index == leaves.count - 1
        if size > 0 && !isLast {
            XCTAssertGreaterThanOrEqual(size, TextRope.Node.minChunkUTF8, "Leaf \(index) has \(size) UTF-8 bytes, min is \(TextRope.Node.minChunkUTF8)", file: file, line: line)
        }
    }
}

private func verifySummaries(_ node: TextRope.Node, file: StaticString, line: UInt) {
    if node.isLeaf {
        let expected = TextRope.Summary.of(node.chunk)
        XCTAssertEqual(node.summary, expected, "Leaf summary mismatch: stored \(node.summary), recomputed \(expected)", file: file, line: line)
    } else {
        var recomputed = TextRope.Summary.zero
        for child in node.children {
            verifySummaries(child, file: file, line: line)
            recomputed.add(child.summary)
        }
        XCTAssertEqual(node.summary, recomputed, "Inner node summary mismatch: stored \(node.summary), recomputed \(recomputed)", file: file, line: line)
    }
}

private func verifyHeight(_ root: TextRope.Node, file: StaticString, line: UInt) {
    func actualHeight(_ node: TextRope.Node) -> UInt8 {
        if node.isLeaf { return 0 }
        var maxChild: UInt8 = 0
        for child in node.children {
            let h = actualHeight(child)
            XCTAssertEqual(child.height, h, "Child height mismatch: stored \(child.height), actual \(h)", file: file, line: line)
            maxChild = max(maxChild, h)
        }
        return maxChild + 1
    }
    let actual = actualHeight(root)
    XCTAssertEqual(root.height, actual, "Root height mismatch: stored \(root.height), actual \(actual)", file: file, line: line)
}
