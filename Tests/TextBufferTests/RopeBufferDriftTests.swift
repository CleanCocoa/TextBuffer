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

    // MARK: - Delete

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
