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

    // MARK: - Stress test

    func testRandomOperationsMatchString() {
        var rng = SeededRNG(state: 42)
        var rope = TextRope("initial content 🎉 你好")
        var string = "initial content 🎉 你好"

        let charset: [String] = [
            "a", "b", "c", "X", "Y", "Z",
            " ", "\n", "\t",
            "é", "ñ", "ü",
            "你", "好", "世", "界",
            "😀", "🎉", "🚀",
            "𝄞", "𝕳",
            "\r\n",
        ]

        func randomString(using rng: inout SeededRNG) -> String {
            let count = Int.random(in: 0...10, using: &rng)
            var result = ""
            for _ in 0..<count {
                result += charset.randomElement(using: &rng)!
            }
            return result
        }

        func validUTF16Offset(_ offset: Int, in str: String) -> Int {
            if offset == 0 || offset >= str.utf16.count { return offset }
            let idx = str.utf16.index(str.utf16.startIndex, offsetBy: offset)
            let scalar = str.unicodeScalars[idx]
            if UTF16.isTrailSurrogate(str.utf16[idx]) {
                return offset - 1
            }
            _ = scalar
            return offset
        }

        for i in 0..<1000 {
            let len = rope.utf16Count
            let op = Int.random(in: 0..<3, using: &rng)

            switch op {
            case 0:
                let rawPos = Int.random(in: 0...len, using: &rng)
                let pos = validUTF16Offset(rawPos, in: string)
                let text = randomString(using: &rng)
                rope.insert(text, at: pos)
                let idx = string.utf16.index(string.utf16.startIndex, offsetBy: pos)
                string.insert(contentsOf: text, at: idx)

            case 1:
                if len > 0 {
                    var start = Int.random(in: 0..<len, using: &rng)
                    start = validUTF16Offset(start, in: string)
                    let maxLen = min(len - start, 20)
                    if maxLen > 0 {
                        var delLen = Int.random(in: 1...maxLen, using: &rng)
                        let endOff = validUTF16Offset(start + delLen, in: string)
                        delLen = endOff - start
                        if delLen > 0 {
                            rope.delete(in: NSRange(location: start, length: delLen))
                            let startIdx = string.utf16.index(string.utf16.startIndex, offsetBy: start)
                            let endIdx = string.utf16.index(startIdx, offsetBy: delLen)
                            string.removeSubrange(startIdx..<endIdx)
                        }
                    }
                }

            case 2:
                if len > 0 {
                    var start = Int.random(in: 0..<len, using: &rng)
                    start = validUTF16Offset(start, in: string)
                    let maxLen = min(len - start, 20)
                    if maxLen > 0 {
                        var repLen = Int.random(in: 1...maxLen, using: &rng)
                        let endOff = validUTF16Offset(start + repLen, in: string)
                        repLen = endOff - start
                        if repLen > 0 {
                            let text = randomString(using: &rng)
                            rope.replace(range: NSRange(location: start, length: repLen), with: text)
                            let startIdx = string.utf16.index(string.utf16.startIndex, offsetBy: start)
                            let endIdx = string.utf16.index(startIdx, offsetBy: repLen)
                            string.replaceSubrange(startIdx..<endIdx, with: text)
                        }
                    }
                }

            default:
                break
            }

            XCTAssertEqual(
                rope.content, string,
                "Content mismatch at iteration \(i), op=\(op)"
            )
            XCTAssertEqual(
                rope.utf16Count, string.utf16.count,
                "UTF-16 count mismatch at iteration \(i), op=\(op)"
            )
        }
    }
}
