//  Copyright © 2026 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

@available(macOS, introduced: 13.0)
final class RopeBufferDriftTests: XCTestCase {

    typealias BufferPair = (msb: MutableStringBuffer, rb: RopeBuffer)

    func bufferPair(_ stringRepresentation: String) throws -> BufferPair {
        let msb = try makeBuffer(stringRepresentation)
        var rb = RopeBuffer("")
        try change(buffer: &rb, to: stringRepresentation)
        return (msb, rb)
    }

    func assertDriftMatch(_ pair: BufferPair, message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pair.rb.content, pair.msb.content, file: file, line: line)
        let msg = message.isEmpty
            ? "RopeBuffer=\(pair.rb.selectedRange) vs MutableStringBuffer=\(pair.msb.selectedRange)"
            : "\(message): RopeBuffer=\(pair.rb.selectedRange) vs MutableStringBuffer=\(pair.msb.selectedRange)"
        XCTAssertEqual(pair.rb.selectedRange, pair.msb.selectedRange, msg, file: file, line: line)
    }

    // MARK: - Insert

    func testInsertBeforeInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.msb.insert("XX", at: 2)
        try pair.rb.insert("XX", at: 2)
        assertDriftMatch(pair)
    }

    func testInsertAtInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.msb.insert("XX", at: 5)
        try pair.rb.insert("XX", at: 5)
        assertDriftMatch(pair)
    }

    func testInsertAfterInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.msb.insert("XX", at: 7)
        try pair.rb.insert("XX", at: 7)
        assertDriftMatch(pair)
    }

    func testInsertBeforeSelection() throws {
        let pair = try bufferPair("你好世界«编程真棒»加油笔记")
        try pair.msb.insert("😀", at: 2)
        try pair.rb.insert("😀", at: 2)
        assertDriftMatch(pair)
    }

    func testInsertAtSelectionStart() throws {
        let pair = try bufferPair("你好世界«编程真棒»加油笔记")
        try pair.msb.insert("éü", at: 4)
        try pair.rb.insert("éü", at: 4)
        assertDriftMatch(pair)
    }

    func testInsertWithinSelection() throws {
        let pair = try bufferPair("你好世界«编程真棒»加油笔记")
        try pair.msb.insert("🎉", at: 6)
        try pair.rb.insert("🎉", at: 6)
        assertDriftMatch(pair)
    }

    func testInsertAtSelectionEnd() throws {
        let pair = try bufferPair("你好世界«编程真棒»加油笔记")
        try pair.msb.insert("ñç", at: 8)
        try pair.rb.insert("ñç", at: 8)
        assertDriftMatch(pair)
    }

    func testInsertAfterSelection() throws {
        let pair = try bufferPair("你好世界«编程真棒»加油笔记")
        try pair.msb.insert("𝄞", at: 10)
        try pair.rb.insert("𝄞", at: 10)
        assertDriftMatch(pair)
    }

    // MARK: - Delete

    func testDeleteBeforeInsertionPoint() throws {
        let pair = try bufferPair("àbcdèˇfghíj")
        try pair.msb.delete(in: .init(location: 1, length: 2))
        try pair.rb.delete(in: .init(location: 1, length: 2))
        assertDriftMatch(pair)
    }

    func testDeleteAfterInsertionPoint() throws {
        let pair = try bufferPair("àbcdèˇfghíj")
        try pair.msb.delete(in: .init(location: 7, length: 2))
        try pair.rb.delete(in: .init(location: 7, length: 2))
        assertDriftMatch(pair)
    }

    func testDeleteOverlappingSelectionStart() throws {
        let pair = try bufferPair("àb«cdèfgh»íj")
        try pair.msb.delete(in: .init(location: 1, length: 3))
        try pair.rb.delete(in: .init(location: 1, length: 3))
        assertDriftMatch(pair)
    }

    func testDeleteOverlappingSelectionEnd() throws {
        let pair = try bufferPair("àb«cdèfgh»íj")
        try pair.msb.delete(in: .init(location: 6, length: 4))
        try pair.rb.delete(in: .init(location: 6, length: 4))
        assertDriftMatch(pair)
    }

    func testDeleteEntireSelection() throws {
        let pair = try bufferPair("àb«cdèfgh»íj")
        try pair.msb.delete(in: .init(location: 2, length: 6))
        try pair.rb.delete(in: .init(location: 2, length: 6))
        assertDriftMatch(pair)
    }

    func testDeleteBeforeSelection() throws {
        let pair = try bufferPair("01234«567»89")
        try pair.msb.delete(in: .init(location: 1, length: 2))
        try pair.rb.delete(in: .init(location: 1, length: 2))
        assertDriftMatch(pair)
    }

    func testDeleteAfterSelection() throws {
        let pair = try bufferPair("01«234»56789")
        try pair.msb.delete(in: .init(location: 7, length: 2))
        try pair.rb.delete(in: .init(location: 7, length: 2))
        assertDriftMatch(pair)
    }

    func testDeleteAcrossInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.msb.delete(in: .init(location: 3, length: 4))
        try pair.rb.delete(in: .init(location: 3, length: 4))
        assertDriftMatch(pair)
    }

    func testDeleteEncompassingSelection() throws {
        let pair = try bufferPair("0123«45»6789")
        try pair.msb.delete(in: .init(location: 2, length: 6))
        try pair.rb.delete(in: .init(location: 2, length: 6))
        assertDriftMatch(pair)
    }

    func testDeleteWithinSelection() throws {
        let pair = try bufferPair("01«234567»89")
        try pair.msb.delete(in: .init(location: 4, length: 2))
        try pair.rb.delete(in: .init(location: 4, length: 2))
        assertDriftMatch(pair)
    }

    // MARK: - Replace

    func testReplaceBeforeSelection() throws {
        let pair = try bufferPair("01234«567»89")
        try pair.msb.replace(range: .init(location: 1, length: 2), with: "ABCD")
        try pair.rb.replace(range: .init(location: 1, length: 2), with: "ABCD")
        assertDriftMatch(pair)
    }

    func testReplaceOverlappingSelection() throws {
        let pair = try bufferPair("àbcdè«fgh»íj")
        try pair.msb.replace(range: .init(location: 4, length: 3), with: "χψ")
        try pair.rb.replace(range: .init(location: 4, length: 3), with: "χψ")
        assertDriftMatch(pair)
    }

    func testReplaceAfterSelection() throws {
        let pair = try bufferPair("àbcdè«fgh»íj")
        try pair.msb.replace(range: .init(location: 8, length: 2), with: "😀")
        try pair.rb.replace(range: .init(location: 8, length: 2), with: "😀")
        assertDriftMatch(pair)
    }

    // MARK: - Composed Character Sequence Reads

    private func assertContentInMatches(_ string: String, _ subrange: NSRange, file: StaticString = #filePath, line: UInt = #line) throws {
        let expected = try MutableStringBuffer(string).content(in: subrange)
        XCTAssertEqual(try RopeBuffer(string).content(in: subrange), expected, "RopeBuffer diverges for \(subrange) in \(string.debugDescription)", file: file, line: line)
        XCTAssertEqual(try SendableRopeBuffer(string).content(in: subrange), expected, "SendableRopeBuffer diverges for \(subrange) in \(string.debugDescription)", file: file, line: line)
    }

    func testContentInRangeCoveringSurrogateHalvesMatchesMutableStringBuffer() throws {
        for range in [NSRange(location: 1, length: 1), NSRange(location: 2, length: 1), NSRange(location: 2, length: 2), NSRange(location: 0, length: 2)] {
            try assertContentInMatches("a😀b", range)
        }
    }

    func testContentInRangeCuttingCombiningMarkMatchesMutableStringBuffer() throws {
        for range in [NSRange(location: 0, length: 1), NSRange(location: 1, length: 1), NSRange(location: 2, length: 1), NSRange(location: 0, length: 2)] {
            try assertContentInMatches("e\u{301}b", range)
        }
    }

    func testContentInPartialGraphemeRangesOnMultiChunkRopeMatchesMutableStringBuffer() throws {
        let string = String(repeating: "x", count: 2046) + "😀" + String(repeating: "y", count: 2046)
        for range in [NSRange(location: 2046, length: 1), NSRange(location: 2047, length: 1), NSRange(location: 2046, length: 2), NSRange(location: 2045, length: 3)] {
            try assertContentInMatches(string, range)
        }
    }

    func testUnsafeCharacterAtSurrogateHalvesAndCombiningMarksMatchesMutableStringBuffer() {
        for (string, locations) in [("a😀b", [0, 1, 2, 3]), ("e\u{301}b", [0, 1, 2])] {
            for location in locations {
                let expected = MutableStringBuffer(string).unsafeCharacter(at: location)
                XCTAssertEqual(RopeBuffer(string).unsafeCharacter(at: location), expected, "RopeBuffer diverges at \(location) in \(string.debugDescription)")
                XCTAssertEqual(SendableRopeBuffer(string).unsafeCharacter(at: location), expected, "SendableRopeBuffer diverges at \(location) in \(string.debugDescription)")
            }
        }
    }

    private func assertUnsafeCharacterMatches(_ string: String, locations: some Sequence<Int>, file: StaticString = #filePath, line: UInt = #line) {
        let msb = MutableStringBuffer(string)
        let rb = RopeBuffer(string)
        let srb = SendableRopeBuffer(string)
        for location in locations {
            let expected = msb.unsafeCharacter(at: location)
            XCTAssertEqual(rb.unsafeCharacter(at: location), expected, "RopeBuffer diverges at \(location)", file: file, line: line)
            XCTAssertEqual(srb.unsafeCharacter(at: location), expected, "SendableRopeBuffer diverges at \(location)", file: file, line: line)
        }
    }

    func testUnsafeCharacterAtRegionalIndicatorRunMatchesMutableStringBuffer() {
        let string = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 100)
        assertUnsafeCharacterMatches(string, locations: 0..<400)
    }

    func testContentInRegionalIndicatorRunMatchesMutableStringBuffer() throws {
        let flags = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 100)
        for range in [
            NSRange(location: 130, length: 1),   // inside the run, past the window radius
            NSRange(location: 131, length: 2),   // starts mid-flag on a trail surrogate
            NSRange(location: 200, length: 40),  // deep inside the run
            NSRange(location: 0, length: 400),   // spans the whole run
            NSRange(location: 396, length: 4),   // ends at the run end
        ] {
            try assertContentInMatches(flags, range)
        }

        let prefixed = String(repeating: "a", count: 100) + flags
        for range in [
            NSRange(location: 90, length: 60),   // spans from prose into the run
            NSRange(location: 231, length: 2),   // starts mid-flag on a trail surrogate, deep in the run
            NSRange(location: 300, length: 100), // inside the run, ending in it
        ] {
            try assertContentInMatches(prefixed, range)
        }
    }

    func testRegionalIndicatorRunAfterProseMatchesMutableStringBuffer() throws {
        // A non-regional-indicator scalar sits immediately left of the run, so the rope's
        // window anchoring is exercised against a run that does not start at offset 0.
        let string = String(repeating: "The quick brown fox. ", count: 10)  // 210 UTF-16 units of prose
            + String(repeating: "\u{1F1E9}\u{1F1EA}", count: 60)           // 240-unit flag run
            + "e\u{301}nd"
        assertUnsafeCharacterMatches(string, locations: 200..<454)
        try assertContentInMatches(string, NSRange(location: 205, length: 140))
        try assertContentInMatches(string, NSRange(location: 340, length: 20))
    }

    func testFlagRunExceedingBackwardWalkCapMatchesMutableStringBuffer() {
        // 5,000 consecutive regional indicators — longer than the rope's fixed 4,096-unit
        // backward-walk cap, so deep reads take the silent full-document fallback.
        let string = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 2500)
        assertUnsafeCharacterMatches(string, locations: [4300, 4302, 5000, 5002, 7001, 9000, 9002, 9998, 9999])
    }

    func testMixedContentEveryOffsetMatchesMutableStringBuffer() {
        // Every non-ASCII feature bracketed by printable ASCII on both sides, so every
        // boundary between a simple ASCII context and a complex cluster context occurs
        // (spec `rope-buffer-drift`: mixed-content every-offset point-read equivalence).
        let string = "The quick 😀 brown e\u{301} fox 👨\u{200D}👩\u{200D}👧\u{200D}👦 jumps\r\nover \u{1F1E9}\u{1F1EA}\u{1F1EB}\u{1F1F7}\u{1F1EE}\u{1F1F9} lazy \u{1F1E9} dogs."
        assertUnsafeCharacterMatches(string, locations: 0..<string.utf16.count)
    }

    func testMixedContentAdjacencyCasesMatchMutableStringBuffer() {
        // Safe current unit with unsafe neighbors on both sides: the single ASCII
        // characters wedged between two non-ASCII features.
        let wedged = "a😀x😀e\u{301}y\u{1F1E9}\u{1F1EA}b"
        // Offsets: a=0, 😀=1..2, x=3, 😀=4..5, e=6, ́=7, y=8, 🇩🇪=9..12, b=13.
        assertUnsafeCharacterMatches(wedged, locations: 0..<wedged.utf16.count)

        // Printable ASCII immediately before and after the CRLF pair, plus the CR and LF
        // offsets themselves — the pinned NSString-vs-grapheme divergence point.
        let crlf = "ab\r\ncd"
        assertUnsafeCharacterMatches(crlf, locations: [1, 2, 3, 4])
        assertUnsafeCharacterMatches(crlf, locations: 0..<crlf.utf16.count)

        // A document that starts and ends with non-ASCII: the document-edge-is-safe rule
        // must never claim an edge offset whose unit is itself outside the safe set.
        let nonASCIIEdges = "😀 middle e\u{301}"
        assertUnsafeCharacterMatches(nonASCIIEdges, locations: 0..<nonASCIIEdges.utf16.count)

        // All-ASCII document edges: offset 0 and the final offset, where the absent
        // neighbor counts as safe.
        let allASCII = "plain ascii document"
        assertUnsafeCharacterMatches(allASCII, locations: [0, allASCII.utf16.count - 1])
    }

    // MARK: - Sequential Operations

    func testSequentialInsertsThenDelete() throws {
        let pair = try bufferPair("abc«defg»hij")

        try pair.msb.insert("1", at: 1)
        try pair.rb.insert("1", at: 1)
        assertDriftMatch(pair, message: "After first insert")

        try pair.msb.insert("2", at: 6)
        try pair.rb.insert("2", at: 6)
        assertDriftMatch(pair, message: "After second insert")

        try pair.msb.insert("3", at: 10)
        try pair.rb.insert("3", at: 10)
        assertDriftMatch(pair, message: "After third insert")

        try pair.msb.delete(in: .init(location: 2, length: 3))
        try pair.rb.delete(in: .init(location: 2, length: 3))
        assertDriftMatch(pair, message: "After delete")
    }
}
