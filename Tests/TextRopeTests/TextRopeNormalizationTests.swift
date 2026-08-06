//  Pins the never-normalize storage guarantee (`rope-core-types`: "TextRope never
//  normalizes and normalization is a caller-boundary policy").
//
//  Every case in this file is **green as of the change that introduced it** — nothing in
//  the package normalizes, and nothing ever has. They exist to keep it that way: a future
//  composition, decomposition, or canonical reordering anywhere on the construction,
//  insert, delete, replace, or materialization path must fail here rather than ship.
//
//  Foundation-free, like the rest of TextRopeTests (ADR-013). The oracle is kept as
//  `[UInt16]` and decoded with the standard library, so no normalizing API is in reach.

import XCTest
@testable import TextRope

final class TextRopeNormalizationTests: XCTestCase {

    // MARK: - Helpers

    private func scalarValues(_ string: String) -> [UInt32] {
        string.unicodeScalars.map(\.value)
    }

    private func oracleString(_ utf16Units: [UInt16]) -> String {
        String(decoding: utf16Units, as: UTF16.self)
    }

    private func leafChunkLengths(_ rope: TextRope) -> [Int] {
        func collect(_ node: TextRope.Node) -> [Int] {
            node.isLeaf ? [node.chunk.utf8.count] : node.children.flatMap(collect)
        }
        return collect(rope.root)
    }

    /// The index of the leaf whose chunk contains the byte at `utf8Offset`.
    private func leafIndex(containingUTF8Offset utf8Offset: Int, in rope: TextRope) -> Int {
        var remaining = utf8Offset
        for (index, length) in leafChunkLengths(rope).enumerated() {
            if remaining < length { return index }
            remaining -= length
        }
        XCTFail("offset \(utf8Offset) beyond rope content")
        return -1
    }

    // MARK: - Construction and insert

    func testInsertingNFDContentLeavesTheBytesNFD() {
        var rope = TextRope("ab")
        rope.insert("e\u{301}", at: 1)

        XCTAssertEqual(
            scalarValues(rope.content), [0x61, 0x65, 0x301, 0x62],
            "the decomposed pair must survive as U+0065 U+0301 — composing it to U+00E9 would be normalization"
        )
        XCTAssertEqual(rope.utf8Count, 5, "a + e + 2-byte combining acute + b")
        XCTAssertEqual(rope.utf16Count, 4)
    }

    func testConstructingFromPrecomposedContentLeavesTheBytesPrecomposed() {
        let rope = TextRope("é")     // U+00E9

        XCTAssertEqual(
            scalarValues(rope.content), [0xE9],
            "the precomposed scalar must survive as one scalar — decomposing it would be normalization"
        )
        XCTAssertEqual(rope.utf8Count, 2)
        XCTAssertEqual(rope.utf16Count, 1)
    }

    // MARK: - Mixed encodings across mutations

    func testMixedEncodingsCoexistAcrossMutations() {
        // One document holding both forms, far enough apart to land in different leaves
        // on a multi-leaf rope, so the guarantee is pinned across a chunk seam too.
        let head = String(repeating: "a", count: 1500)
        let mid = String(repeating: "b", count: 3000)
        let tail = String(repeating: "c", count: 1500)
        let precomposed = "\u{E9}"
        let decomposed = "e\u{301}"
        let initial = head + precomposed + mid + decomposed + tail

        var rope = TextRope(initial)
        var oracle = Array(initial.utf16)

        var precomposedOffset = 1500                        // UTF-16 offset, length 1
        var decomposedOffset = 1500 + 1 + 3000              // UTF-16 offset, length 2

        XCTAssertGreaterThan(leafChunkLengths(rope).count, 1, "the fixture must be multi-leaf")
        XCTAssertNotEqual(
            leafIndex(containingUTF8Offset: 1500, in: rope),
            leafIndex(containingUTF8Offset: 1500 + 2 + 3000, in: rope),
            "the two forms must sit in different leaves, or the chunk-seam half of this pin is not exercised"
        )

        func assertStorageIsFaithful(_ label: String) {
            XCTAssertEqual(
                Array(rope.content.utf8), Array(oracleString(oracle).utf8),
                "\(label): the rope's bytes must equal the oracle's bytes exactly"
            )
            XCTAssertEqual(
                scalarValues(rope.content(in: precomposedOffset ..< precomposedOffset + 1)), [0xE9],
                "\(label): a read over the precomposed form must return the precomposed form"
            )
            XCTAssertEqual(
                scalarValues(rope.content(in: decomposedOffset ..< decomposedOffset + 2)), [0x65, 0x301],
                "\(label): a read over the decomposed form must return the decomposed form"
            )
        }

        assertStorageIsFaithful("after construction")

        // Insert immediately before the precomposed form.
        rope.insert("X", at: precomposedOffset)
        oracle.insert(contentsOf: Array("X".utf16), at: precomposedOffset)
        precomposedOffset += 1
        decomposedOffset += 1
        assertStorageIsFaithful("after inserting before the precomposed form")

        // Insert immediately after the decomposed form.
        let afterDecomposed = decomposedOffset + 2
        rope.insert("Y", at: afterDecomposed)
        oracle.insert(contentsOf: Array("Y".utf16), at: afterDecomposed)
        assertStorageIsFaithful("after inserting after the decomposed form")

        // Delete the inserted "X", again immediately before the precomposed form.
        rope.delete(in: precomposedOffset - 1 ..< precomposedOffset)
        oracle.removeSubrange(precomposedOffset - 1 ..< precomposedOffset)
        precomposedOffset -= 1
        decomposedOffset -= 1
        assertStorageIsFaithful("after deleting before the precomposed form")

        // Replace the inserted "Y" adjacent to the decomposed form.
        let yOffset = decomposedOffset + 2
        rope.replace(range: yOffset ..< yOffset + 1, with: "ZZ")
        oracle.replaceSubrange(yOffset ..< yOffset + 1, with: Array("ZZ".utf16))
        assertStorageIsFaithful("after replacing after the decomposed form")
    }

    // MARK: - Congruence rationale, in test form

    func testCanonicallyEquivalentInputsDoNotConverge() {
        // U+0323 has ccc 220, U+0301 has ccc 230: the same three scalars in different
        // canonical order. Nothing in the package may bring these together.
        let padding = String(repeating: "p", count: 2500)
        var a = TextRope("e\u{301}\u{323}" + padding)
        var b = TextRope("e\u{323}\u{301}" + padding)

        func applyEditScript(to rope: inout TextRope) {
            rope.insert("hello", at: 100)
            rope.delete(in: 500 ..< 700)
            rope.replace(range: 1000 ..< 1010, with: "replacement")
        }
        applyEditScript(to: &a)
        applyEditScript(to: &b)

        XCTAssertEqual(a.utf16Count, b.utf16Count, "the fixtures happen to share a UTF-16 count; the point is the byte order")
        XCTAssertNotEqual(
            Array(a.content.utf8), Array(b.content.utf8),
            "the same edit script applied to code-unit-different inputs must keep them code-unit different"
        )
        XCTAssertNotEqual(a, b, "and they must stay unequal under the code-unit equality contract")

        XCTAssertEqual(
            Array(scalarValues(a.content).prefix(3)), [0x65, 0x301, 0x323],
            "a must not have reordered toward b's canonical order"
        )
        XCTAssertEqual(
            Array(scalarValues(b.content).prefix(3)), [0x65, 0x323, 0x301],
            "b must not have reordered toward a's canonical order"
        )
    }
}
