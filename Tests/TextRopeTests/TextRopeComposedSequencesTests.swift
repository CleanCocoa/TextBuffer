import XCTest
@testable import TextRope
import Foundation

final class TextRopeComposedSequencesTests: XCTestCase {

    /// Asserts that `composedCharacterSequence(at:)` returns, for every offset, exactly what
    /// full-document `NSString` expansion returns — the contract the internal read window
    /// must not be observable through.
    private func assertMatchesFullDocumentExpansion(_ text: String, offsets: some Sequence<Int>, file: StaticString = #filePath, line: UInt = #line) {
        let rope = TextRope(text)
        let nsText = text as NSString
        for offset in offsets {
            let expected = nsText.substring(with: nsText.rangeOfComposedCharacterSequence(at: offset))
            XCTAssertEqual(rope.composedCharacterSequence(at: offset), expected, "composedCharacterSequence(at: \(offset)) diverges from full-document expansion", file: file, line: line)
        }
    }

    // MARK: - Regional indicator pairing (DEF-002)

    func testFlagReadBeyondWindowRadiusIsCorrectlyPaired() {
        let rope = TextRope(String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40))
        XCTAssertEqual(rope.composedCharacterSequence(at: 130), "🇩🇪")
        XCTAssertEqual(rope.composedCharacterSequences(in: NSRange(location: 130, length: 1)), "🇩🇪")
    }

    func testEveryOffsetOfHundredFlagRunMatchesFullDocumentExpansion() {
        let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 100)
        assertMatchesFullDocumentExpansion(text, offsets: 0..<400)
    }

    // MARK: - Regional indicator window-edge cases

    func testFlagRunAtDocumentStartWithWindowStartClampedToZero() {
        let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 70)
        assertMatchesFullDocumentExpansion(text, offsets: 0..<132)
    }

    func testFlagRunAtDocumentEnd() {
        let text = String(repeating: "a", count: 100) + String(repeating: "\u{1F1E9}\u{1F1EA}", count: 60)
        assertMatchesFullDocumentExpansion(text, offsets: 90..<340)
    }

    func testOddLengthFlagRunKeepsLoneTrailingRegionalIndicator() {
        // Alternating letters, so a pairing shift produces a *different* string,
        // not the same flag again. 141 regional indicators: 70 flags plus a lone 🇩.
        let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 70) + "\u{1F1E9}"
        assertMatchesFullDocumentExpansion(text, offsets: 0..<282)
    }

    func testLoneRegionalIndicatorBetweenASCII() {
        let text = String(repeating: "a", count: 200) + "\u{1F1E9}" + String(repeating: "b", count: 50)
        assertMatchesFullDocumentExpansion(text, offsets: 195..<210)
    }

    func testFlagRunSurroundedByASCII() {
        let text = String(repeating: "a", count: 150) + String(repeating: "\u{1F1E9}\u{1F1EA}", count: 50) + String(repeating: "b", count: 150)
        assertMatchesFullDocumentExpansion(text, offsets: 140..<360)
    }

    func testOffsetsStraddlingTheRadiusBoundary() {
        let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 70)
        assertMatchesFullDocumentExpansion(text, offsets: [127, 128, 129, 130, 131])
    }

    func testFlagRunStartingExactlyAtWindowStart() {
        // Run starts at offset 72; a read at 200 computes windowStart = 200 - 128 = 72,
        // landing exactly on the run boundary — not strictly inside the run.
        let text = String(repeating: "a", count: 72) + String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)
        assertMatchesFullDocumentExpansion(text, offsets: 199..<210)
    }

    // MARK: - Rules unaffected by windowing (pins the edge-touch retry, design D3)

    func testCombiningMarksFarIntoDocumentMatchFullDocumentExpansion() {
        let text = String(repeating: "e\u{301}", count: 100)
        assertMatchesFullDocumentExpansion(text, offsets: 0..<200)
    }

    func testZWJEmojiChainsFarIntoDocumentMatchFullDocumentExpansion() {
        let text = String(repeating: "👨‍👩‍👧‍👦", count: 30)
        assertMatchesFullDocumentExpansion(text, offsets: 0..<330)
    }

    func testSkinToneModifierSequencesFarIntoDocumentMatchFullDocumentExpansion() {
        let text = String(repeating: "👋🏽", count: 100)
        assertMatchesFullDocumentExpansion(text, offsets: 0..<400)
    }

    // MARK: - Backward-walk cap fallback

    func testFlagRunLongerThanBackwardWalkCapMatchesFullDocumentExpansion() {
        // 5,000 consecutive regional indicators (10,000 UTF-16 units) — a contiguous run
        // longer than the fixed 4,096-unit backward-walk cap. Offsets 4220...4223 sit just
        // below and just above the cap boundary (windowStart 4092/4094 walk within the cap,
        // 4400+ exceed it); the deep samples all take the silent full-document fallback.
        let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 2500)
        let offsets = [4220, 4221, 4222, 4223] + Array(4400..<4408) + [5000, 5002, 7001, 9000, 9002, 9998, 9999]
        assertMatchesFullDocumentExpansion(text, offsets: offsets)
    }
}
