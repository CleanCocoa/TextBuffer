import XCTest
import Foundation
import TextBuffer

@MainActor
final class TransferableUndoableTests: XCTestCase {
    func testContentDelegatesToBase() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(buffer.content, "hello")
    }

    func testRangeDelegatesToBase() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(buffer.range, NSRange(location: 0, length: 5))
    }

    func testContentInSubrangeDelegatesToBase() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(try buffer.content(in: NSRange(location: 1, length: 3)), "ell")
    }

    func testSelectedRangeGetDelegatesToBase() {
        let base = MutableStringBuffer("hello")
        base.selectedRange = NSRange(location: 2, length: 2)
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 2, length: 2))
    }

    func testSelectedRangeSetDelegatesToBase() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        buffer.selectedRange = NSRange(location: 1, length: 3)
        XCTAssertEqual(base.selectedRange, NSRange(location: 1, length: 3))
    }

    func testInsertMakesCanUndoTrue() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        XCTAssertTrue(buffer.canUndo)
    }

    func testDeleteMakesCanUndoTrue() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.delete(in: NSRange(location: 0, length: 1))
        XCTAssertTrue(buffer.canUndo)
    }

    func testReplaceMakesCanUndoTrue() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.replace(range: NSRange(location: 0, length: 1), with: "Z")
        XCTAssertTrue(buffer.canUndo)
    }

    func testAutoGroupingWrapsStandaloneMutation() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.log.undoableCount, 1)
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func testNoAutoGroupingInsideUndoGrouping() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        buffer.undoGrouping {
            try! buffer.insert("A", at: 0)
            try! buffer.insert("B", at: 1)
        }
        XCTAssertEqual(buffer.log.undoableCount, 1)
    }

    func testUndoAfterInsertRestoresContent() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.content, "Xabc")
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func testUndoAfterInsertRestoresSelection() {
        let base = MutableStringBuffer("abc")
        base.selectedRange = NSRange(location: 1, length: 0)
        let buffer = TransferableUndoable(base)
        let selectionBefore = base.selectedRange
        try! buffer.insert("X", at: 0)
        buffer.undo()
        XCTAssertEqual(buffer.selectedRange, selectionBefore)
    }

    func testUndoAfterDeleteRestoresContent() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.delete(in: NSRange(location: 0, length: 1))
        XCTAssertEqual(buffer.content, "bc")
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func testUndoAfterReplaceRestoresContent() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.replace(range: NSRange(location: 0, length: 3), with: "XYZ")
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func testRedoAfterUndoRestoresContent() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        buffer.undo()
        buffer.redo()
        XCTAssertEqual(buffer.content, "Xabc")
    }

    func testUndoThenRedoIsIdentity() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.replace(range: NSRange(location: 0, length: 3), with: "XYZ")
        let afterEdit = buffer.content
        let selectionAfterEdit = buffer.selectedRange
        buffer.undo()
        buffer.redo()
        XCTAssertEqual(buffer.content, afterEdit)
        XCTAssertEqual(buffer.selectedRange, selectionAfterEdit)
    }

    func testRedoTailTruncatedAfterNewEdit() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        try! buffer.insert("A", at: 0)
        buffer.undo()
        try! buffer.insert("B", at: 0)
        XCTAssertFalse(buffer.canRedo)
        buffer.redo()
        XCTAssertEqual(buffer.content, "B")
    }

    func testSingleGroupTwoInsertsSingleUndoReversesBoth() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        buffer.undoGrouping {
            try! buffer.insert("A", at: 0)
            try! buffer.insert("B", at: 1)
        }
        XCTAssertEqual(buffer.content, "AB")
        buffer.undo()
        XCTAssertEqual(buffer.content, "")
    }

    func testNestedGroupingInnerMergesIntoOuter() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        buffer.undoGrouping {
            try! buffer.insert("A", at: 0)
            buffer.undoGrouping {
                try! buffer.insert("B", at: 1)
                try! buffer.insert("C", at: 2)
            }
        }
        XCTAssertEqual(buffer.content, "ABC")
        buffer.undo()
        XCTAssertEqual(buffer.content, "")
        XCTAssertFalse(buffer.canUndo)
    }

    func testActionNamePropagation() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        buffer.undoGrouping(actionName: "MyAction") {
            try! buffer.insert("A", at: 0)
        }
        XCTAssertEqual(buffer.log.undoActionName, "MyAction")
    }

    func testUndoWhenNothingToUndoIsNoop() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func testRedoWhenNothingToRedoIsNoop() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        buffer.redo()
        XCTAssertEqual(buffer.content, "abc")
    }
}
