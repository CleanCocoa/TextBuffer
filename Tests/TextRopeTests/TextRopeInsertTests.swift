import XCTest
@testable import TextRope

final class TextRopeInsertTests: XCTestCase {
    func testInsertAtStart() {
        var rope = TextRope("hello")
        rope.insert("X", at: 0)
        XCTAssertEqual(rope.content, "Xhello")
    }

    func testInsertAtEnd() {
        var rope = TextRope("hello")
        rope.insert("X", at: 5)
        XCTAssertEqual(rope.content, "helloX")
    }

    func testInsertAtMiddle() {
        var rope = TextRope("hello")
        rope.insert("X", at: 2)
        XCTAssertEqual(rope.content, "heXllo")
    }

    func testInsertEmptyString() {
        var rope = TextRope("hello")
        rope.insert("", at: 2)
        XCTAssertEqual(rope.content, "hello")
    }

    func testInsertCausingLeafSplit() {
        var rope = TextRope("a")
        let large = String(repeating: "B", count: 2500)
        rope.insert(large, at: 1)
        XCTAssertEqual(rope.content, "a" + large)
        XCTAssertEqual(rope.utf8Count, 2501)
        verifyTreeInvariants(rope)
    }

    func testInsertLargeStringIntoSingleLeafRope() {
        var rope = TextRope("a")
        let large = String(repeating: "B", count: 10 * 1024)
        rope.insert(large, at: 1)
        XCTAssertEqual(rope.content, "a" + large)
        XCTAssertEqual(rope.utf8Count, 10241)
        verifyTreeInvariants(rope)
    }

    func testInsertHugeStringIntoFullInnerNode() {
        let base = String(repeating: "A", count: 8 * 2048)
        var rope = TextRope(base)
        verifyTreeInvariants(rope)
        let insert = String(repeating: "Z", count: 100 * 1024)
        rope.insert(insert, at: 0)
        XCTAssertEqual(rope.content, insert + base)
        XCTAssertEqual(rope.utf8Count, base.utf8.count + insert.utf8.count)
        verifyTreeInvariants(rope)
    }

    func testInsertIntoFullInteriorLeafSplitsWithBothHalvesAboveMinimum() {
        let base = String(repeating: "A", count: 4 * 2048)
        var rope = TextRope(base)
        verifyTreeInvariants(rope)
        rope.insert("X", at: 2500)
        var expected = base
        expected.insert("X", at: expected.index(expected.startIndex, offsetBy: 2500))
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.utf8Count, 4 * 2048 + 1)
        verifyTreeInvariants(rope)
    }

    func testInsertMultiByteCharacter() {
        var rope = TextRope("abc")
        rope.insert("\u{1F600}", at: 1)
        XCTAssertEqual(rope.content, "a\u{1F600}bc")
        XCTAssertEqual(rope.utf16Count, 5)
    }

    func testInsertPreservesCOW() {
        var rope = TextRope("hello")
        let copy = rope
        rope.insert("X", at: 0)
        XCTAssertEqual(copy.content, "hello")
        XCTAssertEqual(rope.content, "Xhello")
    }

    func testInsertCascadingSplits() {
        let chunkSize = 2048
        let leafCount = 8 * 8
        let bigString = String(repeating: "A", count: chunkSize * leafCount)
        var rope = TextRope(bigString)
        verifyTreeInvariants(rope)
        let insertContent = String(repeating: "Z", count: chunkSize * 2)
        rope.insert(insertContent, at: 0)
        XCTAssertEqual(rope.content, insertContent + bigString)
        XCTAssertEqual(rope.utf8Count, bigString.utf8.count + insertContent.utf8.count)
        verifyTreeInvariants(rope)
    }

    func testInsertUpdatesUTF16Count() {
        var rope = TextRope("abc")
        XCTAssertEqual(rope.utf16Count, 3)
        rope.insert("de", at: 1)
        XCTAssertEqual(rope.utf16Count, 5)
        rope.insert("\u{1F600}", at: 0)
        XCTAssertEqual(rope.utf16Count, 7)
    }

    func testInsertOnSingleOwnerRopeMutatesInPlace() {
        let blocks = (0..<21).map { _ in String(repeating: "x", count: 2000) }
        var rope = TextRope(blocks.joined())
        XCTAssertEqual(rope.root.children.map(\.children.count), [8, 8, 5])
        let rootBefore = ObjectIdentifier(rope.root)
        let untouchedBefore = ObjectIdentifier(rope.root.children[1])

        rope.insert("Y", at: 41_060)

        XCTAssertEqual(ObjectIdentifier(rope.root), rootBefore)
        XCTAssertEqual(ObjectIdentifier(rope.root.children[1]), untouchedBefore)
    }

    func testInsertOnSharedRopeSharesUnaffectedSubtrees() {
        let blocks = (0..<21).map { _ in String(repeating: "x", count: 2000) }
        let original = TextRope(blocks.joined())
        XCTAssertEqual(original.root.children.map(\.children.count), [8, 8, 5])

        var copy = original
        copy.insert("Y", at: 41_060)

        XCTAssertTrue(copy.root !== original.root, "root must be path-copied")
        XCTAssertTrue(copy.root.children[2] !== original.root.children[2], "subtree on the insert path must be path-copied")

        XCTAssertTrue(copy.root.children[0] === original.root.children[0], "untouched subtree must stay shared")
        XCTAssertTrue(copy.root.children[1] === original.root.children[1], "untouched subtree must stay shared")
        for i in 0..<4 {
            XCTAssertTrue(
                copy.root.children[2].children[i] === original.root.children[2].children[i],
                "untouched sibling leaf \(i) must stay shared"
            )
        }

        XCTAssertEqual(original.content, blocks.joined())
        XCTAssertEqual(copy.utf16Count, original.utf16Count + 1)
    }

    func testInsertAtOffsetInsideSurrogatePairLandsAtScalarBoundary() {
        var rope = TextRope("a😀b")
        rope.insert("X", at: 2)

        XCTAssertEqual(rope.content, "aX😀b")
        XCTAssertEqual(rope.utf16Count, 5)
        XCTAssertEqual(rope.utf8Count, "aX😀b".utf8.count)
    }

    func testInsertBetweenCRAndLFKeepsContentAndLineCountConsistent() {
        var rope = TextRope("first\r\nsecond")
        XCTAssertEqual(rope.root.summary.lines, 1)

        rope.insert("X", at: 6)

        XCTAssertEqual(rope.content, "first\rX\nsecond")
        XCTAssertEqual(rope.root.summary.lines, 1)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(rope.content))
    }

    func testInsertedCRLFIsNotSplitByTheResultingLeafSplit() {
        let base = String(repeating: "a", count: 2000)
        var rope = TextRope(base)
        XCTAssertTrue(rope.root.isLeaf)

        let inserted = String(repeating: "y", count: 49) + "\r\n" + String(repeating: "z", count: 49)
        rope.insert(inserted, at: 1000)

        var expected = base
        expected.insert(contentsOf: inserted, at: expected.index(expected.startIndex, offsetBy: 1000))
        XCTAssertEqual(rope.content, expected)
        XCTAssertFalse(rope.root.isLeaf, "insert must have grown the rope past one leaf")
        verifyTreeInvariants(rope)
    }

    func testRepeatedInsertionsGrowSingleLeafToThreePlusLevels() {
        var rope = TextRope()
        var oracle = ""
        XCTAssertTrue(rope.root.isLeaf)

        let fragments = ["aé你😀\n", String(repeating: "b", count: 400), "line\r\n你好𝄞"]
        var step = 0
        while Int(rope.root.height) < 3 {
            let fragment = fragments[step % fragments.count]
            let position: Int
            switch step % 3 {
            case 0: position = 0
            case 1: position = TextRopeStressTests.validUTF16Offset(oracle.utf16.count / 2, in: oracle)
            default: position = oracle.utf16.count
            }
            rope.insert(fragment, at: position)
            let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: position)
            oracle.insert(contentsOf: fragment, at: idx)
            step += 1

            if step % 100 == 0 {
                XCTAssertEqual(rope.content, oracle, "diverged at step \(step)")
                verifyTreeInvariants(rope, context: "step \(step)")
            }
        }

        XCTAssertGreaterThanOrEqual(Int(rope.root.height), 3)
        XCTAssertEqual(rope.content, oracle)
        XCTAssertEqual(rope.root.summary, TextRope.Summary.of(oracle))
        verifyTreeInvariants(rope, context: "final")
    }

    func testMultipleInserts() {
        var rope = TextRope("ac")
        rope.insert("b", at: 1)
        XCTAssertEqual(rope.content, "abc")
        rope.insert("d", at: 3)
        XCTAssertEqual(rope.content, "abcd")
        rope.insert("0", at: 0)
        XCTAssertEqual(rope.content, "0abcd")
        rope.insert("X", at: 2)
        XCTAssertEqual(rope.content, "0aXbcd")
    }
}
