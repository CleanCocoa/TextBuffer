//  Copyright © 2026 Christian Tietze. All rights reserved. Distributed under the MIT License.

#if os(macOS)
import XCTest
import TextBuffer

@available(macOS, introduced: 13.0)
@MainActor
final class BufferBehaviorDriftTests: XCTestCase {

    typealias BufferPair = (inMemory: MutableStringBuffer, onScreen: NSTextViewBuffer)

    func bufferPair(_ stringRepresentation: String) throws -> BufferPair {
        let inMemory = try makeBuffer(stringRepresentation)
        let onScreen = textView(inMemory.content)
        try change(buffer: onScreen, to: stringRepresentation)
        return (inMemory, onScreen)
    }

    func assertBehaviorMatch(_ pair: BufferPair, message: String = "", file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(pair.inMemory.content, pair.onScreen.content, file: file, line: line)
        let msg = message.isEmpty
            ? "MutableStringBuffer=\(pair.inMemory.selectedRange) vs NSTextViewBuffer=\(pair.onScreen.selectedRange)"
            : "\(message): MutableStringBuffer=\(pair.inMemory.selectedRange) vs NSTextViewBuffer=\(pair.onScreen.selectedRange)"
        XCTAssertEqual(pair.inMemory.selectedRange, pair.onScreen.selectedRange, msg, file: file, line: line)
    }

    // MARK: - Initial Insertion Point

    func testInitialInsertionPoint_Diverges() {
        let inMemory = MutableStringBuffer("hello")
        let onScreen = textView("hello")
        // Intentionally different defaults: MutableStringBuffer is for programmatic
        // use (start at beginning), NSTextView is for user-facing editing (start at end).
        XCTAssertEqual(inMemory.insertionLocation, 0, "MutableStringBuffer starts at beginning")
        XCTAssertEqual(onScreen.insertionLocation, 5, "NSTextViewBuffer starts at end")
    }

    // MARK: - Insert at Location: Selection Adjustment

    func testInsert_BeforeInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.inMemory.insert("XX", at: 2)
        try pair.onScreen.insert("XX", at: 2)
        assertBehaviorMatch(pair)
    }

    func testInsert_AtInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.inMemory.insert("XX", at: 5)
        try pair.onScreen.insert("XX", at: 5)
        assertBehaviorMatch(pair)
    }

    func testInsert_AfterInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.inMemory.insert("XX", at: 7)
        try pair.onScreen.insert("XX", at: 7)
        assertBehaviorMatch(pair)
    }

    func testInsert_BeforeSelection() throws {
        let pair = try bufferPair("01234«567»89")
        try pair.inMemory.insert("XX", at: 2)
        try pair.onScreen.insert("XX", at: 2)
        assertBehaviorMatch(pair)
    }

    func testInsert_AtSelectionStart() throws {
        let pair = try bufferPair("012«3456»789")
        try pair.inMemory.insert("XX", at: 3)
        try pair.onScreen.insert("XX", at: 3)
        assertBehaviorMatch(pair)
    }

    func testInsert_WithinSelection() throws {
        let pair = try bufferPair("012«3456»789")
        try pair.inMemory.insert("XX", at: 5)
        try pair.onScreen.insert("XX", at: 5)
        assertBehaviorMatch(pair)
    }

    func testInsert_AtSelectionEnd() throws {
        let pair = try bufferPair("012«3456»789")
        try pair.inMemory.insert("XX", at: 7)
        try pair.onScreen.insert("XX", at: 7)
        assertBehaviorMatch(pair)
    }

    func testInsert_AfterSelection() throws {
        let pair = try bufferPair("012«3456»789")
        try pair.inMemory.insert("XX", at: 9)
        try pair.onScreen.insert("XX", at: 9)
        assertBehaviorMatch(pair)
    }

    // MARK: - Delete: Selection Adjustment

    func testDelete_BeforeInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.inMemory.delete(in: .init(location: 1, length: 2))
        try pair.onScreen.delete(in: .init(location: 1, length: 2))
        assertBehaviorMatch(pair)
    }

    func testDelete_AfterInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.inMemory.delete(in: .init(location: 7, length: 2))
        try pair.onScreen.delete(in: .init(location: 7, length: 2))
        assertBehaviorMatch(pair)
    }

    func testDelete_AcrossInsertionPoint() throws {
        let pair = try bufferPair("01234ˇ56789")
        try pair.inMemory.delete(in: .init(location: 3, length: 4))
        try pair.onScreen.delete(in: .init(location: 3, length: 4))
        assertBehaviorMatch(pair)
    }

    func testDelete_WithinSelection() throws {
        let pair = try bufferPair("01«234567»89")
        try pair.inMemory.delete(in: .init(location: 4, length: 2))
        try pair.onScreen.delete(in: .init(location: 4, length: 2))
        assertBehaviorMatch(pair)
    }

    func testDelete_OverlappingSelectionStart() throws {
        let pair = try bufferPair("0123«456»789")
        try pair.inMemory.delete(in: .init(location: 2, length: 4))
        try pair.onScreen.delete(in: .init(location: 2, length: 4))
        assertBehaviorMatch(pair)
    }

    func testDelete_OverlappingSelectionEnd() throws {
        let pair = try bufferPair("0123«456»789")
        try pair.inMemory.delete(in: .init(location: 5, length: 4))
        try pair.onScreen.delete(in: .init(location: 5, length: 4))
        assertBehaviorMatch(pair)
    }

    func testDelete_EntireSelection() throws {
        let pair = try bufferPair("012«3456»789")
        try pair.inMemory.delete(in: .init(location: 3, length: 4))
        try pair.onScreen.delete(in: .init(location: 3, length: 4))
        assertBehaviorMatch(pair)
    }

    func testDelete_EncompassingSelection() throws {
        let pair = try bufferPair("0123«45»6789")
        try pair.inMemory.delete(in: .init(location: 2, length: 6))
        try pair.onScreen.delete(in: .init(location: 2, length: 6))
        assertBehaviorMatch(pair)
    }

    func testDelete_BeforeSelection() throws {
        let pair = try bufferPair("01234«567»89")
        try pair.inMemory.delete(in: .init(location: 1, length: 2))
        try pair.onScreen.delete(in: .init(location: 1, length: 2))
        assertBehaviorMatch(pair)
    }

    func testDelete_AfterSelection() throws {
        let pair = try bufferPair("01«234»56789")
        try pair.inMemory.delete(in: .init(location: 7, length: 2))
        try pair.onScreen.delete(in: .init(location: 7, length: 2))
        assertBehaviorMatch(pair)
    }

    // MARK: - Sequential Operations (Drift Accumulation)

    func testSequentialInserts_DriftAccumulation() throws {
        let pair = try bufferPair("abc«defg»hij")

        try pair.inMemory.insert("1", at: 1)
        try pair.onScreen.insert("1", at: 1)

        try pair.inMemory.insert("2", at: 6)
        try pair.onScreen.insert("2", at: 6)

        try pair.inMemory.insert("3", at: 10)
        try pair.onScreen.insert("3", at: 10)

        assertBehaviorMatch(pair, message: "After 3 sequential inserts")
    }

    func testMixedInsertDelete_DriftAccumulation() throws {
        let pair = try bufferPair("hello «world» test")

        try pair.inMemory.insert("XX", at: 3)
        try pair.onScreen.insert("XX", at: 3)

        try pair.inMemory.delete(in: .init(location: 0, length: 2))
        try pair.onScreen.delete(in: .init(location: 0, length: 2))

        try pair.inMemory.insert("YY", at: 10)
        try pair.onScreen.insert("YY", at: 10)

        assertBehaviorMatch(pair, message: "After mixed ops")
    }
}
#endif
