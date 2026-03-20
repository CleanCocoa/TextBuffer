import XCTest
import TextBuffer

final class SendableRopeBufferTests: XCTestCase {

    // MARK: - Read accessors

    func testContentReturnsRopeContent() {
        let buffer = SendableRopeBuffer("hello")
        XCTAssertEqual(buffer.content, "hello")
    }

    func testRangeCoversFullContent() {
        let buffer = SendableRopeBuffer("hello")
        XCTAssertEqual(buffer.range, NSRange(location: 0, length: 5))
    }

    func testEmptyBufferHasZeroRange() {
        let buffer = SendableRopeBuffer()
        XCTAssertEqual(buffer.range, NSRange(location: 0, length: 0))
    }

    func testInitWithSelection() {
        let buffer = SendableRopeBuffer("hello", selectedRange: NSRange(location: 2, length: 3))
        XCTAssertEqual(buffer.content, "hello")
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 2, length: 3))
    }

    func testContentInSubrange() throws {
        let buffer = SendableRopeBuffer("hello world")
        let sub = try buffer.content(in: NSRange(location: 6, length: 5))
        XCTAssertEqual(sub, "world")
    }

    func testUnsafeCharacterReturnsSingleCharacter() {
        let buffer = SendableRopeBuffer("abc")
        XCTAssertEqual(buffer.unsafeCharacter(at: 1), "b")
    }

    // MARK: - Selection

    func testInitialSelectionIsZero() {
        let buffer = SendableRopeBuffer("hello")
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 0, length: 0))
    }

    func testSelectUpdatesSelectedRange() {
        var buffer = SendableRopeBuffer("hello")
        buffer.select(NSRange(location: 1, length: 3))
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 1, length: 3))
    }

    func testIsSelectingText() {
        var buffer = SendableRopeBuffer("hello")
        XCTAssertFalse(buffer.isSelectingText)
        buffer.selectedRange = NSRange(location: 0, length: 5)
        XCTAssertTrue(buffer.isSelectingText)
    }

    func testInsertionLocationGetAndSet() {
        var buffer = SendableRopeBuffer("hello")
        XCTAssertEqual(buffer.insertionLocation, 0)
        buffer.insertionLocation = 3
        XCTAssertEqual(buffer.insertionLocation, 3)
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 3, length: 0))
    }

    // MARK: - Mutation + bounds checking

    func testInsertAtLocation() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.insert("X", at: 2)
        XCTAssertEqual(buffer.content, "heXllo")
    }

    func testInsertAtLocationOutOfRangeThrows() {
        var buffer = SendableRopeBuffer("hi")
        XCTAssertThrowsError(try buffer.insert("X", at: 10)) { error in
            XCTAssertTrue(error is BufferAccessFailure)
        }
    }

    func testDeleteInRange() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.delete(in: NSRange(location: 1, length: 3))
        XCTAssertEqual(buffer.content, "ho")
    }

    func testDeleteOutOfRangeThrows() {
        var buffer = SendableRopeBuffer("hi")
        XCTAssertThrowsError(try buffer.delete(in: NSRange(location: 0, length: 10))) { error in
            XCTAssertTrue(error is BufferAccessFailure)
        }
    }

    func testReplaceRange() throws {
        var buffer = SendableRopeBuffer("hello world")
        try buffer.replace(range: NSRange(location: 0, length: 5), with: "howdy")
        XCTAssertEqual(buffer.content, "howdy world")
    }

    func testReplaceOutOfRangeThrows() {
        var buffer = SendableRopeBuffer("hi")
        XCTAssertThrowsError(try buffer.replace(range: NSRange(location: 0, length: 10), with: "X")) { error in
            XCTAssertTrue(error is BufferAccessFailure)
        }
    }

    func testContentInSubrangeOutOfRangeThrows() {
        let buffer = SendableRopeBuffer("hi")
        XCTAssertThrowsError(try buffer.content(in: NSRange(location: 0, length: 10))) { error in
            XCTAssertTrue(error is BufferAccessFailure)
        }
    }

    func testCharacterAtOutOfRangeThrows() {
        let buffer = SendableRopeBuffer("hi")
        XCTAssertThrowsError(try buffer.character(at: 10)) { error in
            XCTAssertTrue(error is BufferAccessFailure)
        }
    }

    // MARK: - Selection adjustment

    func testInsertBeforeSelectionShiftsRight() throws {
        var buffer = SendableRopeBuffer("hello")
        buffer.selectedRange = NSRange(location: 3, length: 0)
        try buffer.insert("XX", at: 1)
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 5, length: 0))
    }

    func testInsertAfterSelectionDoesNotShift() throws {
        var buffer = SendableRopeBuffer("hello")
        buffer.selectedRange = NSRange(location: 1, length: 0)
        try buffer.insert("XX", at: 3)
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 1, length: 0))
    }

    func testDeleteBeforeSelectionShiftsLeft() throws {
        var buffer = SendableRopeBuffer("hello")
        buffer.selectedRange = NSRange(location: 4, length: 0)
        try buffer.delete(in: NSRange(location: 0, length: 2))
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 2, length: 0))
    }

    func testReplaceAdjustsSelection() throws {
        var buffer = SendableRopeBuffer("hello world")
        buffer.selectedRange = NSRange(location: 8, length: 0)
        try buffer.replace(range: NSRange(location: 0, length: 5), with: "hi")
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 5, length: 0))
    }

    // MARK: - modifying

    func testModifyingChecksBounds() {
        var buffer = SendableRopeBuffer("hi")
        XCTAssertThrowsError(
            try buffer.modifying(affectedRange: NSRange(location: 0, length: 100)) { }
        ) { error in
            XCTAssertTrue(error is BufferAccessFailure)
        }
    }

    func testModifyingExecutesBlock() throws {
        var buffer = SendableRopeBuffer("hello")
        let result = try buffer.modifying(affectedRange: NSRange(location: 0, length: 5)) { 42 }
        XCTAssertEqual(result, 42)
    }

    // MARK: - Auto-grouping

    func testSingleInsertIsAutoGrouped() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.insert("X", at: 0)
        XCTAssertTrue(buffer.log.canUndo)
        XCTAssertEqual(buffer.log.undoableCount, 1)
    }

    func testSingleDeleteIsAutoGrouped() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.delete(in: NSRange(location: 0, length: 2))
        XCTAssertTrue(buffer.log.canUndo)
        XCTAssertEqual(buffer.log.undoableCount, 1)
    }

    func testSingleReplaceIsAutoGrouped() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.replace(range: NSRange(location: 0, length: 5), with: "world")
        XCTAssertTrue(buffer.log.canUndo)
        XCTAssertEqual(buffer.log.undoableCount, 1)
    }

    // MARK: - Explicit grouping

    func testUndoGroupingBundlesMultipleOperations() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.undoGrouping(actionName: "batch") { buf in
            try buf.insert("A", at: 0)
            try buf.insert("B", at: 1)
        }
        XCTAssertEqual(buffer.log.undoableCount, 1)
        XCTAssertEqual(buffer.log.undoActionName, "batch")
        XCTAssertEqual(buffer.content, "ABhello")
    }

    func testBeginEndUndoGroupBundlesOperations() throws {
        var buffer = SendableRopeBuffer("hello")
        buffer.beginUndoGroup(actionName: "manual")
        try buffer.insert("A", at: 0)
        try buffer.insert("B", at: 1)
        buffer.endUndoGroup()
        XCTAssertEqual(buffer.log.undoableCount, 1)
        XCTAssertEqual(buffer.log.undoActionName, "manual")
    }

    // MARK: - Undo/Redo

    func testUndoAfterInsertRestoresContent() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.content, "Xhello")

        _ = buffer.undo()
        XCTAssertEqual(buffer.content, "hello")
    }

    func testUndoAfterDeleteRestoresContent() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.delete(in: NSRange(location: 0, length: 5))
        XCTAssertEqual(buffer.content, "")

        _ = buffer.undo()
        XCTAssertEqual(buffer.content, "hello")
    }

    func testUndoAfterReplaceRestoresContent() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.replace(range: NSRange(location: 0, length: 5), with: "world")

        _ = buffer.undo()
        XCTAssertEqual(buffer.content, "hello")
    }

    func testUndoRestoresSelection() throws {
        var buffer = SendableRopeBuffer("hello")
        buffer.selectedRange = NSRange(location: 2, length: 3)
        try buffer.replace(range: NSRange(location: 2, length: 3), with: "LP")

        let restored = buffer.undo()
        XCTAssertEqual(restored, NSRange(location: 2, length: 3))
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 2, length: 3))
    }

    func testRedoAfterUndoRestoresContent() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.insert("X", at: 0)
        _ = buffer.undo()
        _ = buffer.redo()
        XCTAssertEqual(buffer.content, "Xhello")
    }

    func testUndoRedoUndoRoundTrip() throws {
        var buffer = SendableRopeBuffer("hello")
        try buffer.replace(range: NSRange(location: 0, length: 5), with: "world")

        _ = buffer.undo()
        XCTAssertEqual(buffer.content, "hello")

        _ = buffer.redo()
        XCTAssertEqual(buffer.content, "world")

        _ = buffer.undo()
        XCTAssertEqual(buffer.content, "hello")
    }

    func testUndoGroupedOperationsReversesAll() throws {
        var buffer = SendableRopeBuffer("")
        try buffer.undoGrouping { buf in
            try buf.insert("hello", at: 0)
            try buf.insert(" world", at: 5)
        }
        XCTAssertEqual(buffer.content, "hello world")

        _ = buffer.undo()
        XCTAssertEqual(buffer.content, "")
    }

    func testUndoReturnsNilWhenNothingToUndo() {
        var buffer = SendableRopeBuffer("hello")
        XCTAssertNil(buffer.undo())
    }

    func testRedoReturnsNilWhenNothingToRedo() {
        var buffer = SendableRopeBuffer("hello")
        XCTAssertNil(buffer.redo())
    }

    // MARK: - COW semantics

    func testCopyOnWriteIndependence() throws {
        let original = SendableRopeBuffer("hello")
        var copy = original
        try copy.insert("X", at: 0)
        XCTAssertEqual(original.content, "hello")
        XCTAssertEqual(copy.content, "Xhello")
    }

    func testCopyOnWriteUndoIndependence() throws {
        var original = SendableRopeBuffer("hello")
        try original.insert("X", at: 0)

        var copy = original
        _ = copy.undo()

        XCTAssertEqual(original.content, "Xhello")
        XCTAssertEqual(copy.content, "hello")
    }

    // MARK: - Comparator

    func testComparatorContentOnly() throws {
        var a = SendableRopeBuffer("hello")
        let b = SendableRopeBuffer("hello")
        try a.insert("X", at: 0)
        _ = a.undo()

        let byContent = SendableRopeBuffer.comparator(.content)
        XCTAssertTrue(byContent(a, b))
    }

    func testComparatorContentDetectsDifference() {
        let a = SendableRopeBuffer("hello")
        let b = SendableRopeBuffer("world")
        let byContent = SendableRopeBuffer.comparator(.content)
        XCTAssertFalse(byContent(a, b))
    }

    func testComparatorSelectionOnly() {
        var a = SendableRopeBuffer("hello")
        var b = SendableRopeBuffer("world")
        a.selectedRange = NSRange(location: 2, length: 0)
        b.selectedRange = NSRange(location: 2, length: 0)
        let bySelection = SendableRopeBuffer.comparator(.selection)
        XCTAssertTrue(bySelection(a, b))
    }

    func testComparatorSelectionDetectsDifference() {
        var a = SendableRopeBuffer("hello")
        var b = SendableRopeBuffer("hello")
        a.selectedRange = NSRange(location: 0, length: 5)
        b.selectedRange = NSRange(location: 0, length: 0)
        let bySelection = SendableRopeBuffer.comparator(.selection)
        XCTAssertFalse(bySelection(a, b))
    }

    func testComparatorContentAndSelection() throws {
        var a = SendableRopeBuffer("hello")
        try a.insert("X", at: 0)
        _ = a.undo()

        let b = SendableRopeBuffer("hello")

        let byContentAndSelection = SendableRopeBuffer.comparator(.content, .selection)
        XCTAssertTrue(byContentAndSelection(a, b))
    }

    func testComparatorUndoHistoryDetectsDifference() throws {
        var a = SendableRopeBuffer("hello")
        try a.insert("X", at: 0)
        _ = a.undo()

        let b = SendableRopeBuffer("hello")

        let withHistory = SendableRopeBuffer.comparator(.content, .undoHistory)
        XCTAssertFalse(withHistory(a, b))
    }

    func testComparatorAllComponents() {
        let a = SendableRopeBuffer("hello")
        let b = SendableRopeBuffer("hello")
        let byAll = SendableRopeBuffer.comparator(.content, .selection, .undoHistory)
        XCTAssertTrue(byAll(a, b))
    }

    // MARK: - Sendable compile-time

    func testSendableInSendableClosure() {
        let buffer = SendableRopeBuffer("hello")
        let closure: @Sendable () -> String = { buffer.content }
        XCTAssertEqual(closure(), "hello")
    }

    func testSendableInTaskGroup() async {
        let results = await withTaskGroup(of: String.self, returning: [String].self) { group in
            for i in 0..<10 {
                let buffer = SendableRopeBuffer("note \(i)")
                group.addTask {
                    return buffer.content
                }
            }
            var collected: [String] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }
        XCTAssertEqual(results.count, 10)
    }
}
