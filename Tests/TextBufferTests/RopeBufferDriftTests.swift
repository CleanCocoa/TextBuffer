//  Copyright © 2026 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

@available(macOS, introduced: 13.0)
final class RopeBufferDriftTests: XCTestCase {

    typealias BufferPair = (msb: MutableStringBuffer, rb: RopeBuffer)

    func bufferPair(_ stringRepresentation: String) throws -> BufferPair {
        let msb = try makeBuffer(stringRepresentation)
        let rb = RopeBuffer("")
        try change(buffer: rb, to: stringRepresentation)
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
