import XCTest
import Foundation
@testable import TextRope

struct SeededRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9e3779b97f4a7c15
        var z = state
        z = (z ^ (z >> 30)) &* 0xbf58476d1ce4e5b9
        z = (z ^ (z >> 27)) &* 0x94d049bb133111eb
        return z ^ (z >> 31)
    }
}

final class TextRopeStressTests: XCTestCase {

    // MARK: - Construction round-trips

    func testConstructionASCII() {
        let strings = [
            "",
            "a",
            "hello world",
            String(repeating: "abcdefghij", count: 500),
            "the quick brown fox jumps over the lazy dog",
            "1234567890!@#$%^&*()_+-=[]{}|;':\",./<>?",
        ]
        for s in strings {
            let rope = TextRope(s)
            XCTAssertEqual(rope.content, s)
            XCTAssertEqual(rope.utf16Count, s.utf16.count)
            XCTAssertEqual(rope.utf8Count, s.utf8.count)
        }
    }

    func testConstructionMultiByte() {
        let strings = [
            "😀🎉🚀",
            "你好世界",
            "café résumé naïve",
            "αβγδεζηθ",
            "🇺🇸🇬🇧🇯🇵",
            "Hello 你好 مرحبا こんにちは 🌍",
        ]
        for s in strings {
            let rope = TextRope(s)
            XCTAssertEqual(rope.content, s)
            XCTAssertEqual(rope.utf16Count, s.utf16.count)
            XCTAssertEqual(rope.utf8Count, s.utf8.count)
        }
    }

    func testConstructionCRLF() {
        let strings = [
            "\r\n",
            "\r\n\r\n\r\n",
            "line1\r\nline2\r\nline3",
            "a\r\nb\r\nc\r\n",
            String(repeating: "x\r\n", count: 1000),
        ]
        for s in strings {
            let rope = TextRope(s)
            XCTAssertEqual(rope.content, s)
            XCTAssertEqual(rope.utf16Count, s.utf16.count)
        }
    }

    func testConstructionSurrogatePairs() {
        let strings = [
            "𝄞",
            "𝕳𝕰𝕷𝕷𝕺",
            "𝄞𝄡𝄢",
            "a𝄞b𝕳c",
            "𝟘𝟙𝟚𝟛𝟜",
        ]
        for s in strings {
            let rope = TextRope(s)
            XCTAssertEqual(rope.content, s)
            XCTAssertEqual(rope.utf16Count, s.utf16.count)
            XCTAssertEqual(rope.utf8Count, s.utf8.count)
        }
    }

    func testConstructionRoundTripAcrossChunkSizeBoundaries() {
        let strings = [
            "",
            String(repeating: "x", count: 500),
            String(repeating: "x", count: 2048),
            String(repeating: "x", count: 3000),
            String(repeating: "né😀\n", count: 15_000),
        ]
        for s in strings {
            let rope = TextRope(s)
            XCTAssertEqual(rope.content, s, "round-trip failed for \(s.utf8.count) UTF-8 bytes")
            XCTAssertEqual(rope.utf16Count, s.utf16.count)
            XCTAssertEqual(rope.utf8Count, s.utf8.count)
            XCTAssertEqual(rope.root.summary.lines, Self.newlineCount(in: s))
        }
        XCTAssertGreaterThan(strings.last!.utf8.count, 100_000)
    }

    // MARK: - Edge cases

    func testInsertAtEveryPosition() {
        let base = String(repeating: "a", count: 100)
        for i in 0...100 {
            var rope = TextRope(base)
            rope.insert("X", at: i)
            var expected = base
            let idx = expected.utf16.index(expected.utf16.startIndex, offsetBy: i)
            expected.insert("X", at: idx)
            XCTAssertEqual(rope.content, expected, "Insert at position \(i) failed")
        }
    }

    func testDeleteEverySubrange() {
        let base = "abcdefghij"
        let len = base.utf16.count
        for start in 0..<len {
            for end in (start + 1)...len {
                var rope = TextRope(base)
                let range = NSRange(location: start, length: end - start)
                rope.delete(in: range)
                var expected = base
                let startIdx = expected.utf16.index(expected.utf16.startIndex, offsetBy: start)
                let endIdx = expected.utf16.index(expected.utf16.startIndex, offsetBy: end)
                expected.removeSubrange(startIdx..<endIdx)
                XCTAssertEqual(rope.content, expected, "Delete range (\(start), \(end - start)) failed")
            }
        }
    }

    func testReplaceWithVariousLengths() {
        let base = "Hello, World!"
        let replaceRange = NSRange(location: 5, length: 2)

        var shorter = TextRope(base)
        shorter.replace(range: replaceRange, with: "X")
        XCTAssertEqual(shorter.content, "HelloXWorld!")

        var same = TextRope(base)
        same.replace(range: replaceRange, with: "AB")
        XCTAssertEqual(same.content, "HelloABWorld!")

        var longer = TextRope(base)
        longer.replace(range: replaceRange, with: "ABCDE")
        XCTAssertEqual(longer.content, "HelloABCDEWorld!")

        var empty = TextRope(base)
        empty.replace(range: replaceRange, with: "")
        XCTAssertEqual(empty.content, "HelloWorld!")

        var multi = TextRope(base)
        multi.replace(range: replaceRange, with: "😀🎉")
        XCTAssertEqual(multi.content, "Hello😀🎉World!")
    }

    // MARK: - COW independence

    func testCOWInsertIndependence() {
        let rope = TextRope("hello world")
        var copy = rope
        copy.insert("X", at: 0)
        XCTAssertEqual(rope.content, "hello world")
        XCTAssertEqual(copy.content, "Xhello world")
    }

    func testCOWDeleteIndependence() {
        let rope = TextRope("hello world")
        var copy = rope
        copy.delete(in: NSRange(location: 0, length: 5))
        XCTAssertEqual(rope.content, "hello world")
        XCTAssertEqual(copy.content, " world")
    }

    func testCOWChainedCopies() {
        let original = TextRope("abcdefghij")
        var copies = (0..<5).map { _ in original }

        copies[0].insert("0", at: 0)
        copies[1].insert("1", at: 5)
        copies[2].delete(in: NSRange(location: 0, length: 3))
        copies[3].replace(range: NSRange(location: 2, length: 4), with: "XY")
        copies[4].insert("😀", at: 10)

        XCTAssertEqual(original.content, "abcdefghij")
        XCTAssertEqual(copies[0].content, "0abcdefghij")
        XCTAssertEqual(copies[1].content, "abcde1fghij")
        XCTAssertEqual(copies[2].content, "defghij")
        XCTAssertEqual(copies[3].content, "abXYghij")
        XCTAssertEqual(copies[4].content, "abcdefghij😀")
    }

    func testCOWIndependenceOnMultiChunkRope() {
        let original = String(repeating: "abcdé\n", count: 1500)
        let rope = TextRope(original)
        XCTAssertFalse(rope.root.isLeaf)

        var inserted = rope
        inserted.insert("😀", at: 3000)
        XCTAssertEqual(rope.content, original, "insert on copy mutated original")

        var deleted = rope
        deleted.delete(in: NSRange(location: 100, length: 2000))
        XCTAssertEqual(rope.content, original, "delete on copy mutated original")

        var replaced = rope
        replaced.replace(range: NSRange(location: 500, length: 1000), with: "你好")
        XCTAssertEqual(rope.content, original, "replace on copy mutated original")
    }

    func testCOWUnderSustainedMutation() {
        var rng = SeededRNG(state: 7)
        var oracle = ""
        for _ in 0..<4000 {
            oracle += Self.stressCharset.randomElement(using: &rng)!
        }
        let original = TextRope(oracle)
        let originalContent = original.content

        var copy = original
        for i in 0..<100 {
            let op = Int.random(in: 0..<3, using: &rng)
            switch op {
            case 0:
                let pos = Self.validUTF16Offset(Int.random(in: 0...oracle.utf16.count, using: &rng), in: oracle)
                let text = Self.randomString(using: &rng)
                copy.insert(text, at: pos)
                let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: pos)
                oracle.insert(contentsOf: text, at: idx)
            case 1:
                if let range = Self.randomValidRange(in: oracle, using: &rng) {
                    copy.delete(in: range)
                    let startIdx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: range.location)
                    let endIdx = oracle.utf16.index(startIdx, offsetBy: range.length)
                    oracle.removeSubrange(startIdx..<endIdx)
                }
            default:
                if let range = Self.randomValidRange(in: oracle, using: &rng) {
                    let text = Self.randomString(using: &rng)
                    copy.replace(range: range, with: text)
                    let startIdx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: range.location)
                    let endIdx = oracle.utf16.index(startIdx, offsetBy: range.length)
                    oracle.replaceSubrange(startIdx..<endIdx, with: text)
                }
            }
            XCTAssertEqual(original.content, originalContent, "original changed after mutation \(i)")
            XCTAssertEqual(copy.content, oracle, "copy diverged from oracle at mutation \(i)")
        }
    }

    // MARK: - CRLF invariant edge cases

    private func makeRopeWithCRLFAtChunkBoundary() -> (rope: TextRope, oracle: String) {
        let oracle = String(repeating: "a", count: 2048) + "\r\n" + String(repeating: "b", count: 2048)
        let rope = TextRope(oracle)
        verifyTreeInvariants(rope, context: "construction")
        return (rope, oracle)
    }

    func testInsertNearCRLFAtChunkBoundary() {
        for offset in [2047, 2048, 2049, 2050] {
            for inserted in ["Xé", "\n", "\nX", "X\r", "\r"] {
                var (rope, oracle) = makeRopeWithCRLFAtChunkBoundary()
                rope.insert(inserted, at: offset)
                let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: offset)
                oracle.insert(contentsOf: inserted, at: idx)

                XCTAssertEqual(rope.content, oracle, "content mismatch after inserting \(inserted.debugDescription) at \(offset)")
                XCTAssertEqual(rope.root.summary.lines, Self.newlineCount(in: oracle), "line count mismatch after inserting \(inserted.debugDescription) at \(offset)")
                verifyTreeInvariants(rope, context: "insert \(inserted.debugDescription) at \(offset)")
            }
        }
    }

    func testInsertAtChunkBoundaryAfterBareCRAtChunkEnd() {
        let left = String(repeating: "a", count: 2047) + "\r"
        let boundary = left.utf16.count
        for offset in [boundary - 1, boundary, boundary + 1] {
            for inserted in ["\n", "\nX", "X\r", "\r"] {
                var oracle = left + String(repeating: "b", count: 2048)
                var rope = TextRope(oracle)
                verifyTreeInvariants(rope, context: "construction")

                rope.insert(inserted, at: offset)
                let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: offset)
                oracle.insert(contentsOf: inserted, at: idx)

                XCTAssertEqual(rope.content, oracle, "content mismatch after inserting \(inserted.debugDescription) at \(offset)")
                XCTAssertEqual(rope.root.summary.lines, Self.newlineCount(in: oracle), "line count mismatch after inserting \(inserted.debugDescription) at \(offset)")
                verifyTreeInvariants(rope, context: "insert \(inserted.debugDescription) at \(offset)")
            }
        }
    }

    func testDeleteAndReplaceAcrossCRLFPair() {
        let base = String(repeating: "a", count: 1000) + "\r\n" + String(repeating: "b", count: 1000)

        var deleteCR = TextRope(base)
        deleteCR.delete(in: NSRange(location: 1000, length: 1))
        XCTAssertEqual(deleteCR.content, String(repeating: "a", count: 1000) + "\n" + String(repeating: "b", count: 1000))
        XCTAssertEqual(deleteCR.root.summary.lines, 1)

        var deleteLF = TextRope(base)
        deleteLF.delete(in: NSRange(location: 1001, length: 1))
        XCTAssertEqual(deleteLF.content, String(repeating: "a", count: 1000) + "\r" + String(repeating: "b", count: 1000))
        XCTAssertEqual(deleteLF.root.summary.lines, 0)

        var replacePair = TextRope(base)
        replacePair.replace(range: NSRange(location: 999, length: 4), with: "X")
        XCTAssertEqual(replacePair.content, String(repeating: "a", count: 999) + "X" + String(repeating: "b", count: 999))
        XCTAssertEqual(replacePair.root.summary.lines, 0)

        for rope in [deleteCR, deleteLF, replacePair] {
            verifyTreeInvariants(rope)
        }
    }

    func testLineCountStaysConsistentAcrossCRLFMutations() {
        var rope = TextRope(String(repeating: "line\r\n", count: 500))
        var oracle = String(repeating: "line\r\n", count: 500)

        func assertLineCount(_ step: String) {
            XCTAssertEqual(rope.root.summary.lines, Self.newlineCount(in: oracle), "line count diverged: \(step)")
            XCTAssertEqual(rope.content, oracle, "content diverged: \(step)")
        }

        rope.insert("\r\n", at: 300)
        let insertIdx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: 300)
        oracle.insert(contentsOf: "\r\n", at: insertIdx)
        assertLineCount("insert CRLF")

        rope.delete(in: NSRange(location: 4, length: 2))
        let delStart = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: 4)
        let delEnd = oracle.utf16.index(delStart, offsetBy: 2)
        oracle.removeSubrange(delStart..<delEnd)
        assertLineCount("delete a CRLF pair")

        rope.delete(in: NSRange(location: 100, length: 1))
        let halfStart = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: 100)
        let halfEnd = oracle.utf16.index(halfStart, offsetBy: 1)
        oracle.removeSubrange(halfStart..<halfEnd)
        assertLineCount("delete a single unit inside the text")

        rope.replace(range: NSRange(location: 50, length: 20), with: "\n\r\n\n")
        let repStart = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: 50)
        let repEnd = oracle.utf16.index(repStart, offsetBy: 20)
        oracle.replaceSubrange(repStart..<repEnd, with: "\n\r\n\n")
        assertLineCount("replace with mixed newlines")

        verifyTreeInvariants(rope, context: "after CRLF mutations")
    }

    // MARK: - Summary correctness

    func testSummaryAfterMixedOperations() {
        var rope = TextRope()
        var string = ""

        rope.insert("Hello, World!", at: 0)
        string = "Hello, World!"
        XCTAssertEqual(rope.utf16Count, string.utf16.count)
        XCTAssertEqual(rope.utf8Count, string.utf8.count)

        rope.insert("😀", at: 5)
        string.insert(contentsOf: "😀", at: string.utf16.index(string.utf16.startIndex, offsetBy: 5))
        XCTAssertEqual(rope.utf16Count, string.utf16.count)
        XCTAssertEqual(rope.utf8Count, string.utf8.count)
        XCTAssertEqual(rope.content, string)

        rope.delete(in: NSRange(location: 0, length: 3))
        let delStart = string.utf16.startIndex
        let delEnd = string.utf16.index(delStart, offsetBy: 3)
        string.removeSubrange(delStart..<delEnd)
        XCTAssertEqual(rope.utf16Count, string.utf16.count)
        XCTAssertEqual(rope.utf8Count, string.utf8.count)
        XCTAssertEqual(rope.content, string)

        rope.replace(range: NSRange(location: 1, length: 2), with: "你好")
        let rStart = string.utf16.index(string.utf16.startIndex, offsetBy: 1)
        let rEnd = string.utf16.index(rStart, offsetBy: 2)
        string.replaceSubrange(rStart..<rEnd, with: "你好")
        XCTAssertEqual(rope.utf16Count, string.utf16.count)
        XCTAssertEqual(rope.utf8Count, string.utf8.count)
        XCTAssertEqual(rope.content, string)

        rope.insert(String(repeating: "x", count: 500), at: rope.utf16Count)
        string += String(repeating: "x", count: 500)
        XCTAssertEqual(rope.utf16Count, string.utf16.count)
        XCTAssertEqual(rope.utf8Count, string.utf8.count)
        XCTAssertEqual(rope.content, string)
    }

    // MARK: - Surrogate pair edge cases

    func testDeleteAtSurrogateBoundaries() {
        var deleteEmoji = TextRope("a🎉b")
        deleteEmoji.delete(in: NSRange(location: 1, length: 2))
        XCTAssertEqual(deleteEmoji.content, "ab")
        XCTAssertEqual(deleteEmoji.utf16Count, 2)

        var deleteBefore = TextRope("a🎉b")
        deleteBefore.delete(in: NSRange(location: 0, length: 1))
        XCTAssertEqual(deleteBefore.content, "🎉b")
        XCTAssertEqual(deleteBefore.utf16Count, 3)

        var deleteMultiple = TextRope("a🎉🚀😀b")
        deleteMultiple.delete(in: NSRange(location: 1, length: 6))
        XCTAssertEqual(deleteMultiple.content, "ab")
        XCTAssertEqual(deleteMultiple.utf16Count, 2)
    }

    func testReplaceAtSurrogateBoundaries() {
        var replaceEmoji = TextRope("a🎉b")
        replaceEmoji.replace(range: NSRange(location: 1, length: 2), with: "XY")
        XCTAssertEqual(replaceEmoji.content, "aXYb")
        XCTAssertEqual(replaceEmoji.utf16Count, 4)

        let family = "👨\u{200D}👩\u{200D}👧"
        var replacePartial = TextRope(family)
        let range = NSRange(location: 2, length: 3)
        replacePartial.replace(range: range, with: "X")
        let expected = (family as NSString).replacingCharacters(in: range, with: "X")
        XCTAssertEqual(replacePartial.content, expected)
        XCTAssertEqual(replacePartial.utf16Count, expected.utf16.count)
        XCTAssertEqual(replacePartial.utf8Count, expected.utf8.count)
    }

    func testDeleteAndReplaceEmojiNearChunkBoundary() {
        let base = String(repeating: "a", count: 2046) + "😀" + String(repeating: "b", count: 2046)
        let emojiRange = NSRange(location: 2046, length: 2)

        let constructed = TextRope(base)
        XCTAssertEqual(constructed.content, base)
        verifyTreeInvariants(constructed, context: "construction")

        var deleted = constructed
        deleted.delete(in: emojiRange)
        let expectedAfterDelete = (base as NSString).replacingCharacters(in: emojiRange, with: "")
        XCTAssertEqual(deleted.content, expectedAfterDelete)
        XCTAssertEqual(deleted.utf16Count, expectedAfterDelete.utf16.count)
        verifyTreeInvariants(deleted, context: "delete emoji")

        var replaced = constructed
        replaced.replace(range: emojiRange, with: "🚀🎉")
        let expectedAfterReplace = (base as NSString).replacingCharacters(in: emojiRange, with: "🚀🎉")
        XCTAssertEqual(replaced.content, expectedAfterReplace)
        XCTAssertEqual(replaced.utf16Count, expectedAfterReplace.utf16.count)
        XCTAssertEqual(replaced.utf8Count, expectedAfterReplace.utf8.count)
        verifyTreeInvariants(replaced, context: "replace emoji")
    }

    // MARK: - Repeated single-character operations

    private static func singleCharacters(count: Int, seed: UInt64) -> [String] {
        var rng = SeededRNG(state: seed)
        let pool = stressCharset.filter { $0.utf16.count <= 2 && $0 != "\r\n" }
        return (0..<count).map { _ in pool.randomElement(using: &rng)! }
    }

    func testThousandSingleCharInsertsAtPositionZero() {
        let chars = Self.singleCharacters(count: 1000, seed: 1)
        var rope = TextRope()
        for char in chars {
            rope.insert(char, at: 0)
        }
        let expected = chars.reversed().joined()
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.utf16Count, expected.utf16.count)
        verifyTreeInvariants(rope)
    }

    func testThousandSingleCharAppendsAtEnd() {
        let chars = Self.singleCharacters(count: 1000, seed: 2)
        var rope = TextRope()
        for char in chars {
            rope.insert(char, at: rope.utf16Count)
        }
        let expected = chars.joined()
        XCTAssertEqual(rope.content, expected)
        XCTAssertEqual(rope.utf16Count, expected.utf16.count)
        verifyTreeInvariants(rope)
    }

    func testBuildUpThenTearDownLeavesEmptyRope() {
        let chars = Self.singleCharacters(count: 1000, seed: 3)
        var rope = TextRope()
        for char in chars {
            rope.insert(char, at: rope.utf16Count)
        }
        XCTAssertEqual(rope.content, chars.joined())

        for char in chars.reversed() {
            let length = char.utf16.count
            rope.delete(in: NSRange(location: rope.utf16Count - length, length: length))
        }

        XCTAssertTrue(rope.isEmpty)
        XCTAssertEqual(rope.content, "")
        XCTAssertEqual(rope.utf16Count, 0)
        XCTAssertEqual(rope.utf8Count, 0)
    }

    func testAlternatingSingleCharInsertAndDeleteMatchesOracle() {
        var rng = SeededRNG(state: 4)
        let pool = Self.stressCharset.filter { $0 != "\r\n" }
        var rope = TextRope()
        var oracle = ""

        for i in 0..<2000 {
            if i % 2 == 0 {
                let char = pool.randomElement(using: &rng)!
                let pos = Self.validUTF16Offset(Int.random(in: 0...oracle.utf16.count, using: &rng), in: oracle)
                rope.insert(char, at: pos)
                let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: pos)
                oracle.insert(contentsOf: char, at: idx)
            } else if !oracle.isEmpty {
                let start = Self.validUTF16Offset(Int.random(in: 0..<oracle.utf16.count, using: &rng), in: oracle)
                var length = 1
                if start + 1 < oracle.utf16.count {
                    let next = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: start + 1)
                    if UTF16.isTrailSurrogate(oracle.utf16[next]) { length = 2 }
                }
                rope.delete(in: NSRange(location: start, length: length))
                let startIdx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: start)
                let endIdx = oracle.utf16.index(startIdx, offsetBy: length)
                oracle.removeSubrange(startIdx..<endIdx)
            }

            XCTAssertEqual(rope.content, oracle, "diverged from oracle at operation \(i)")
            if i % 100 == 0 {
                verifyTreeInvariants(rope, context: "operation \(i)")
            }
        }
        verifyTreeInvariants(rope, context: "final")
    }

    func testFiveHundredEmojiInsertsAtRandomPositions() {
        var rng = SeededRNG(state: 5)
        var rope = TextRope()
        var oracle = ""

        for _ in 0..<500 {
            let pos = Self.validUTF16Offset(Int.random(in: 0...oracle.utf16.count, using: &rng), in: oracle)
            rope.insert("😀", at: pos)
            let idx = oracle.utf16.index(oracle.utf16.startIndex, offsetBy: pos)
            oracle.insert(contentsOf: "😀", at: idx)
        }

        XCTAssertEqual(rope.utf16Count, 1000)
        XCTAssertEqual(rope.content, oracle)
        verifyTreeInvariants(rope)
    }

    // MARK: - Stress test

    private static let stressCharset: [String] = [
        "a", "b", "c", "X", "Y", "Z",
        " ", "\n", "\t",
        "é", "ñ", "ü",
        "你", "好", "世", "界",
        "😀", "🎉", "🚀",
        "𝄞", "𝕳",
        "\r\n",
    ]

    static func randomString(using rng: inout SeededRNG, maxLength: Int = 12) -> String {
        let count = Int.random(in: 0...maxLength, using: &rng)
        var result = ""
        for _ in 0..<count {
            result += stressCharset.randomElement(using: &rng)!
        }
        return result
    }

    static func validUTF16Offset(_ offset: Int, in string: String) -> Int {
        if offset == 0 || offset >= string.utf16.count { return offset }
        let idx = string.utf16.index(string.utf16.startIndex, offsetBy: offset)
        if UTF16.isTrailSurrogate(string.utf16[idx]) {
            return offset - 1
        }
        return offset
    }

    static func randomValidRange(in string: String, maxLength: Int = 10, using rng: inout SeededRNG) -> NSRange? {
        let len = string.utf16.count
        guard len > 0 else { return nil }
        let start = validUTF16Offset(Int.random(in: 0..<len, using: &rng), in: string)
        let maxLen = min(len - start, maxLength)
        guard maxLen > 0 else { return nil }
        let rawLength = Int.random(in: 1...maxLen, using: &rng)
        let length = validUTF16Offset(start + rawLength, in: string) - start
        guard length > 0 else { return nil }
        return NSRange(location: start, length: length)
    }

    static func newlineCount(in string: String) -> Int {
        var count = 0
        for byte in string.utf8 where byte == UInt8(ascii: "\n") {
            count += 1
        }
        return count
    }

    func testRandomOperationsMatchString() {
        for seed in [UInt64(0), 42, 12345, UInt64.max] {
            runStressTest(seed: seed, operations: 10_000)
        }
    }

    private func runStressTest(seed: UInt64, operations: Int) {
        print("TextRope stress test: seed \(seed), \(operations) operations")
        var rng = SeededRNG(state: seed)

        var string = ""
        for _ in 0..<12_000 {
            string += Self.stressCharset.randomElement(using: &rng)!
        }
        var rope = TextRope(string)

        var insertCount = 0
        var deleteCount = 0
        var replaceCount = 0
        var sawInnerNodeChildren = false

        for i in 0..<operations {
            let context = "seed \(seed), iteration \(i)"
            let len = rope.utf16Count
            let op = Int.random(in: 0..<3, using: &rng)

            switch op {
            case 0:
                insertCount += 1
                let pos = Self.validUTF16Offset(Int.random(in: 0...len, using: &rng), in: string)
                let text = Self.randomString(using: &rng)
                rope.insert(text, at: pos)
                let idx = string.utf16.index(string.utf16.startIndex, offsetBy: pos)
                string.insert(contentsOf: text, at: idx)

            case 1:
                deleteCount += 1
                if let range = Self.randomValidRange(in: string, using: &rng) {
                    rope.delete(in: range)
                    let startIdx = string.utf16.index(string.utf16.startIndex, offsetBy: range.location)
                    let endIdx = string.utf16.index(startIdx, offsetBy: range.length)
                    string.removeSubrange(startIdx..<endIdx)
                }

            case 2:
                replaceCount += 1
                if let range = Self.randomValidRange(in: string, using: &rng) {
                    let text = Self.randomString(using: &rng)
                    rope.replace(range: range, with: text)
                    let startIdx = string.utf16.index(string.utf16.startIndex, offsetBy: range.location)
                    let endIdx = string.utf16.index(startIdx, offsetBy: range.length)
                    string.replaceSubrange(startIdx..<endIdx, with: text)
                }

            default:
                break
            }

            XCTAssertEqual(
                rope.content, string,
                "Content mismatch at \(context), op=\(op)"
            )
            XCTAssertEqual(
                rope.utf16Count, string.utf16.count,
                "UTF-16 count mismatch at \(context), op=\(op)"
            )
            XCTAssertEqual(
                rope.utf8Count, string.utf8.count,
                "UTF-8 count mismatch at \(context), op=\(op)"
            )
            XCTAssertEqual(
                rope.root.summary.lines, Self.newlineCount(in: string),
                "Line count mismatch at \(context), op=\(op)"
            )

            if i % 100 == 0 {
                verifyTreeInvariants(rope, context: context)
            }

            if i == operations / 2 {
                XCTAssertFalse(
                    rope.root.isLeaf,
                    "\(context): root is a single leaf; stress run never grew a tree"
                )
                XCTAssertTrue(
                    !rope.root.children.isEmpty && rope.root.children.allSatisfy { !$0.isLeaf },
                    "\(context): expected root children to be inner nodes, root height is \(rope.root.height)"
                )
                sawInnerNodeChildren = true
            }
        }

        verifyTreeInvariants(rope, context: "seed \(seed), final")
        XCTAssertTrue(sawInnerNodeChildren, "seed \(seed): mid-run tree-depth check never executed")
        XCTAssertGreaterThanOrEqual(
            Int(rope.root.height), 2,
            "seed \(seed): final tree height \(rope.root.height) never reached multiple inner levels"
        )

        func leafCount(_ node: TextRope.Node) -> Int {
            node.isLeaf ? 1 : node.children.reduce(0) { $0 + leafCount($1) }
        }
        print("TextRope stress test: seed \(seed) final tree height \(rope.root.height), \(leafCount(rope.root)) leaves, \(rope.utf8Count) UTF-8 bytes, \(rope.utf16Count) UTF-16 units")

        let total = insertCount + deleteCount + replaceCount
        XCTAssertEqual(total, operations, "seed \(seed): operation count mismatch")
        for (name, count) in [("insert", insertCount), ("delete", deleteCount), ("replace", replaceCount)] {
            XCTAssertGreaterThan(count, 0, "seed \(seed): no \(name) operations were generated")
            let share = Double(count) / Double(total)
            XCTAssertGreaterThanOrEqual(share, 0.15, "seed \(seed): \(name) is only \(share * 100)% of operations, minimum is 15%")
            XCTAssertLessThanOrEqual(share, 0.60, "seed \(seed): \(name) is \(share * 100)% of operations, maximum is 60%")
        }
    }
}
