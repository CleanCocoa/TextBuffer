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
        // The `String` assertion stays for its readable failure output; the byte assertion
        // decides fidelity. Keeping both localizes the diagnosis: `String ==` is canonical
        // equivalence, so a failure that trips only the byte assertion is specifically a
        // normalization or canonical-ordering divergence on the rope side.
        XCTAssertEqual(pair.rb.content, pair.msb.content, file: file, line: line)
        XCTAssertEqual(
            Array(pair.rb.content.utf8), Array(pair.msb.content.utf8),
            "content is String-equal but byte-unequal: a normalization or canonical-ordering divergence between RopeBuffer and the MutableStringBuffer oracle",
            file: file, line: line
        )
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

    // MARK: - Text Analysis Queries

    /// Oracle comparison for `lineRange(for:)`: both rope-backed buffer types must return
    /// exactly what `MutableStringBuffer` (Foundation's `NSString.lineRange(for:)`) returns.
    private func assertLineRangeMatches(_ string: String, ranges: [NSRange], file: StaticString = #filePath, line: UInt = #line) throws {
        let msb = MutableStringBuffer(string)
        let rb = RopeBuffer(string)
        let srb = SendableRopeBuffer(string)
        for searchRange in ranges {
            let expected = try msb.lineRange(for: searchRange)
            XCTAssertEqual(try rb.lineRange(for: searchRange), expected, "RopeBuffer lineRange diverges for \(searchRange) in \(string.debugDescription)", file: file, line: line)
            XCTAssertEqual(try srb.lineRange(for: searchRange), expected, "SendableRopeBuffer lineRange diverges for \(searchRange) in \(string.debugDescription)", file: file, line: line)
        }
    }

    /// Oracle comparison for `wordRange(for:)`: both rope-backed buffer types must return
    /// exactly what `MutableStringBuffer` (the full-document `computeWordRange`) returns.
    private func assertWordRangeMatches(_ string: String, ranges: [NSRange], file: StaticString = #filePath, line: UInt = #line) throws {
        let msb = MutableStringBuffer(string)
        let rb = RopeBuffer(string)
        let srb = SendableRopeBuffer(string)
        for searchRange in ranges {
            let expected = try msb.wordRange(for: searchRange)
            XCTAssertEqual(try rb.wordRange(for: searchRange), expected, "RopeBuffer wordRange diverges for \(searchRange) in \(string.debugDescription)", file: file, line: line)
            XCTAssertEqual(try srb.wordRange(for: searchRange), expected, "SendableRopeBuffer wordRange diverges for \(searchRange) in \(string.debugDescription)", file: file, line: line)
        }
    }

    /// Every zero-length range in the document, `0...count`.
    private func allZeroLengthRanges(in string: String) -> [NSRange] {
        return (0...string.utf16.count).map { NSRange(location: $0, length: 0) }
    }

    func testLineRangeDelimiterZooMatchesMutableStringBuffer() throws {
        for delimiter in ["\n", "\r", "\r\n", "\u{0085}", "\u{2028}", "\u{2029}"] {
            // Two content lines, an empty line, and a trailing line without a terminator.
            let string = "aa" + delimiter + "bbb" + delimiter + delimiter + "cc"
            let count = string.utf16.count
            var ranges = allZeroLengthRanges(in: string)
            ranges.append(NSRange(location: 3, length: 1))                          // inside a line
            ranges.append(NSRange(location: 0, length: count))                      // whole document
            ranges.append(NSRange(location: 1, length: count - 2))                  // spanning multiple lines
            ranges.append(NSRange(location: 0, length: 2 + delimiter.utf16.count))  // ends exactly on a line start
            try assertLineRangeMatches(string, ranges: ranges)
        }
    }

    func testLineRangeMixedDelimitersMatchMutableStringBuffer() throws {
        let string = "a\nb\rc\r\nd\u{0085}e\u{2028}f\u{2029}g"
        let count = string.utf16.count
        var ranges = allZeroLengthRanges(in: string)
        for length in [1, 2, 3, 5] {
            for location in 0...(count - length) {
                ranges.append(NSRange(location: location, length: length))
            }
        }
        try assertLineRangeMatches(string, ranges: ranges)
    }

    func testLineRangeInsideCRLFMatchesMutableStringBuffer() throws {
        // NSString treats a location between the `\r` and `\n` of a CRLF pair as part of
        // the line the CRLF terminates; the pair is one delimiter, longest match preferred.
        try assertLineRangeMatches("ab\r\ncd\r\n", ranges: [
            NSRange(location: 3, length: 0),  // between \r and \n
            NSRange(location: 7, length: 0),  // between the second \r and \n
            NSRange(location: 2, length: 1),  // covers only the \r
            NSRange(location: 3, length: 1),  // covers only the \n
            NSRange(location: 0, length: 3),  // ends between \r and \n
            NSRange(location: 2, length: 2),  // covers exactly the CRLF
        ])
    }

    func testLineRangeDocumentEdgesMatchMutableStringBuffer() throws {
        // Trailing line without a terminator, ranges at document start and end.
        let string = "ab\ncd"
        try assertLineRangeMatches(string, ranges: allZeroLengthRanges(in: string) + [
            NSRange(location: 0, length: 0),
            NSRange(location: 5, length: 0),
            NSRange(location: 0, length: 5),
            NSRange(location: 3, length: 2),
            NSRange(location: 0, length: 3),  // ends exactly on the "cd" line start
        ])

        // Trailing delimiter: the zero-length range at the document end is its own empty line.
        try assertLineRangeMatches("ab\n", ranges: allZeroLengthRanges(in: "ab\n"))

        // Delimiter-free document: the whole document is one line.
        let plain = "delimiter free document"
        try assertLineRangeMatches(plain, ranges: allZeroLengthRanges(in: plain) + [
            NSRange(location: 0, length: plain.utf16.count),
            NSRange(location: 4, length: 9),
        ])

        try assertLineRangeMatches("", ranges: [NSRange(location: 0, length: 0)])
    }

    func testLineRangeAcrossChunkSeamsMatchesMutableStringBuffer() throws {
        // >4KiB of 32-unit CRLF-terminated lines: the rope holds multiple leaves, and the
        // CRLF pairs land near the 2048-byte chunk region. Sweeping every offset forces
        // scans across every leaf seam.
        let line = String(repeating: "x", count: 30) + "\r\n"
        let manyShortLines = String(repeating: line, count: 160)  // 5,120 UTF-16 units
        var ranges = allZeroLengthRanges(in: manyShortLines)
        for location in stride(from: 0, through: 5000, by: 97) {
            ranges.append(NSRange(location: location, length: 100))  // spans multiple lines and seams
        }
        try assertLineRangeMatches(manyShortLines, ranges: ranges)

        // Lines longer than the 128-unit scan block, one longer than a 2048-unit leaf:
        // the block-walks must cross block boundaries (offsets 127/128/129 relative to a
        // delimiter) and leaf seams mid-line. Sweeping every offset covers them all.
        let longLines = "aa\r\n"
            + String(repeating: "y", count: 300) + "\r\n"
            + String(repeating: "z", count: 4000) + "\r\n"
            + "tail"
        try assertLineRangeMatches(longLines, ranges: allZeroLengthRanges(in: longLines))
    }

    func testWordRangeZooMatchesMutableStringBuffer() throws {
        for string in [
            "don't stop believing",       // apostrophes
            "a well-known example",       // hyphens
            "😀😀😀 abc😀def",             // emoji words, emoji adjacent to letters
            "word",                       // document edges without surrounding whitespace
        ] {
            var ranges = allZeroLengthRanges(in: string)
            ranges.append(NSRange(location: 0, length: string.utf16.count))
            ranges.append(NSRange(location: 2, length: min(3, string.utf16.count - 2)))
            try assertWordRangeMatches(string, ranges: ranges)
        }
    }

    func testWordRangeCrossingWindowRadiusMatchesMutableStringBuffer() throws {
        // A word longer than 256 UTF-16 units: the initial 128-unit window radius cannot
        // contain it, so the result must come from a doubled window.
        let longWord = String(repeating: "a", count: 300)
        let string = "start " + longWord + " end"
        try assertWordRangeMatches(string, ranges: [
            NSRange(location: 6, length: 0),        // word start
            NSRange(location: 156, length: 0),      // word middle
            NSRange(location: 306, length: 0),      // word end
            NSRange(location: 146, length: 20),     // span inside the word
            NSRange(location: 0, length: 0),        // document start
            NSRange(location: string.utf16.count, length: 0),  // document end
        ])
    }

    func testWordRangeWhitespaceRunsMatchMutableStringBuffer() throws {
        let run = String(repeating: "  \n ", count: 75)  // 300 units of spaces and newlines

        // Words on both sides, nearest word beyond the initial window radius.
        let interior = "word" + run + "tail"
        try assertWordRangeMatches(interior, ranges: [
            NSRange(location: 154, length: 0),  // mid-run, both words beyond the radius
            NSRange(location: 20, length: 0),   // word only upstream within the radius
            NSRange(location: 290, length: 0),  // word only downstream within the radius
            NSRange(location: 100, length: 50), // non-empty range inside the run
            NSRange(location: 4, length: 0),
            NSRange(location: 304, length: 0),
        ])

        // One-sided runs: whitespace reaches the document edge on one side.
        let leading = run + "word"
        try assertWordRangeMatches(leading, ranges: [
            NSRange(location: 0, length: 0),
            NSRange(location: 150, length: 0),
            NSRange(location: 299, length: 0),
        ])
        let trailing = "word" + run
        try assertWordRangeMatches(trailing, ranges: [
            NSRange(location: 150, length: 0),
            NSRange(location: 5, length: 0),
            NSRange(location: trailing.utf16.count, length: 0),
        ])

        // All-whitespace document: no word anywhere, however far the window grows.
        try assertWordRangeMatches(run, ranges: [
            NSRange(location: 0, length: 0),
            NSRange(location: 150, length: 0),
            NSRange(location: 150, length: 20),
            NSRange(location: run.utf16.count, length: 0),
        ])
    }

    func testTextAnalysisQueriesThrowOutOfRangeIdenticallyToMutableStringBuffer() throws {
        let string = "0123456789"
        let msb = MutableStringBuffer(string)
        let rb = RopeBuffer(string)
        let srb = SendableRopeBuffer(string)

        func caught(_ body: () throws -> NSRange) -> BufferAccessFailure? {
            do { _ = try body(); return nil } catch { return error as? BufferAccessFailure }
        }

        for invalid in [
            NSRange(location: 20, length: 0),         // past the end
            NSRange(location: 5, length: 10),         // length overruns the end
            NSRange(location: -1, length: 0),         // negative location
            NSRange(location: NSNotFound, length: 0), // NSNotFound
        ] {
            guard let expectedLine = caught({ try msb.lineRange(for: invalid) }),
                  let expectedWord = caught({ try msb.wordRange(for: invalid) })
            else {
                XCTFail("MutableStringBuffer did not throw for \(invalid); the zoo expects an out-of-range oracle")
                continue
            }
            for (label, lineFailure, wordFailure) in [
                ("RopeBuffer", caught({ try rb.lineRange(for: invalid) }), caught({ try rb.wordRange(for: invalid) })),
                ("SendableRopeBuffer", caught({ try srb.lineRange(for: invalid) }), caught({ try srb.wordRange(for: invalid) })),
            ] {
                XCTAssertEqual(lineFailure?.label, expectedLine.label, "\(label) lineRange failure diverges for \(invalid)")
                XCTAssertEqual(lineFailure?.context, expectedLine.context, "\(label) lineRange failure diverges for \(invalid)")
                XCTAssertEqual(wordFailure?.label, expectedWord.label, "\(label) wordRange failure diverges for \(invalid)")
                XCTAssertEqual(wordFailure?.context, expectedWord.context, "\(label) wordRange failure diverges for \(invalid)")
            }
        }
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

    // MARK: - Equality dialect (DEF-018)

    /// The two `Buffer` conformers are meant to be interchangeable, but before
    /// `fix-equality-contract` they answered oppositely on a canonical reorder:
    /// `MutableStringBuffer.==` goes through `NSString.isEqual` (code-unit) while
    /// `RopeBuffer.==` fell through `TextRope.==` to Swift `String ==` (canonical).
    func testEqualityDialectAgreesWithOracleOnCanonicallyReorderedContent() {
        // Same three scalars, different canonical order (U+0323 ccc 220, U+0301 ccc 230).
        let first = "e\u{301}\u{323}"
        let second = "e\u{323}\u{301}"

        XCTAssertTrue(first == second, "premise: Swift String == reports the two contents equal")
        XCTAssertNotEqual(Array(first.utf8), Array(second.utf8), "premise: the two contents differ in UTF-8 code units")

        XCTAssertNotEqual(
            MutableStringBuffer(first), MutableStringBuffer(second),
            "the NSString-backed oracle has always answered unequal here"
        )
        XCTAssertNotEqual(
            RopeBuffer(first), RopeBuffer(second),
            "RopeBuffer must agree with the oracle — this is the cross-buffer drift named in DEF-018"
        )
    }
}
