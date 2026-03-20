import XCTest
import TextBuffer

final class OperationLogTests: XCTestCase {
    func testSingleInsert_UndoRestoresContent() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "hi ", at: 0)))
        try! buffer.insert("hi ", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 3, length: 0))

        let selection = log.undo(on: buffer)

        XCTAssertEqual(buffer.content, "hello")
        XCTAssertEqual(selection, NSRange(location: 0, length: 0))
    }

    func testSingleInsert_RedoRestoresContent() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "hi ", at: 0)))
        try! buffer.insert("hi ", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 3, length: 0))

        _ = log.undo(on: buffer)
        let selection = log.redo(on: buffer)

        XCTAssertEqual(buffer.content, "hi hello")
        XCTAssertEqual(selection, NSRange(location: 3, length: 0))
    }

    func testSingleDelete_UndoRestoresContent() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 5, length: 0))
        log.record(BufferOperation(kind: .delete(range: NSRange(location: 0, length: 5), deletedContent: "hello")))
        try! buffer.delete(in: NSRange(location: 0, length: 5))
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 0))

        let selection = log.undo(on: buffer)

        XCTAssertEqual(buffer.content, "hello")
        XCTAssertEqual(selection, NSRange(location: 5, length: 0))
    }

    func testSingleDelete_RedoRestoresContent() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 5, length: 0))
        log.record(BufferOperation(kind: .delete(range: NSRange(location: 0, length: 5), deletedContent: "hello")))
        try! buffer.delete(in: NSRange(location: 0, length: 5))
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 0))

        _ = log.undo(on: buffer)
        let selection = log.redo(on: buffer)

        XCTAssertEqual(buffer.content, "")
        XCTAssertEqual(selection, NSRange(location: 0, length: 0))
    }

    func testSingleReplace_UndoRestoresContent() {
        let buffer = MutableStringBuffer("hello world")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 5))
        log.record(BufferOperation(kind: .replace(range: NSRange(location: 0, length: 5), oldContent: "hello", newContent: "howdy")))
        try! buffer.replace(range: NSRange(location: 0, length: 5), with: "howdy")
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 5))

        let selection = log.undo(on: buffer)

        XCTAssertEqual(buffer.content, "hello world")
        XCTAssertEqual(selection, NSRange(location: 0, length: 5))
    }

    func testSingleReplace_RedoRestoresContent() {
        let buffer = MutableStringBuffer("hello world")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 5))
        log.record(BufferOperation(kind: .replace(range: NSRange(location: 0, length: 5), oldContent: "hello", newContent: "howdy")))
        try! buffer.replace(range: NSRange(location: 0, length: 5), with: "howdy")
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 5))

        _ = log.undo(on: buffer)
        let selection = log.redo(on: buffer)

        XCTAssertEqual(buffer.content, "howdy world")
        XCTAssertEqual(selection, NSRange(location: 0, length: 5))
    }

    func testMultiOperationGroup_UndoAppliesInReverseOrder() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "hello", at: 0)))
        try! buffer.insert("hello", at: 0)
        log.record(BufferOperation(kind: .insert(content: " world", at: 5)))
        try! buffer.insert(" world", at: 5)
        log.endUndoGroup(selectionAfter: NSRange(location: 11, length: 0))

        XCTAssertEqual(buffer.content, "hello world")

        _ = log.undo(on: buffer)

        XCTAssertEqual(buffer.content, "")
    }

    func testMultiOperationGroup_RedoAppliesInForwardOrder() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "hello", at: 0)))
        try! buffer.insert("hello", at: 0)
        log.record(BufferOperation(kind: .insert(content: " world", at: 5)))
        try! buffer.insert(" world", at: 5)
        log.endUndoGroup(selectionAfter: NSRange(location: 11, length: 0))

        _ = log.undo(on: buffer)
        _ = log.redo(on: buffer)

        XCTAssertEqual(buffer.content, "hello world")
    }

    func testNestedGroups_MergeOperationsIntoParent() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "hello", at: 0)))
        try! buffer.insert("hello", at: 0)

        log.beginUndoGroup(selectionBefore: NSRange(location: 5, length: 0))
        log.record(BufferOperation(kind: .insert(content: " world", at: 5)))
        try! buffer.insert(" world", at: 5)
        log.endUndoGroup(selectionAfter: NSRange(location: 11, length: 0))

        log.endUndoGroup(selectionAfter: NSRange(location: 11, length: 0))

        XCTAssertEqual(log.history.count, 1)
        XCTAssertEqual(log.history[0].operations.count, 2)

        _ = log.undo(on: buffer)

        XCTAssertEqual(buffer.content, "")
    }

    func testActionName_PromotedFromNestedWhenParentHasNone() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0), actionName: nil)
        log.record(BufferOperation(kind: .insert(content: "a", at: 0)))
        try! buffer.insert("a", at: 0)

        log.beginUndoGroup(selectionBefore: NSRange(location: 1, length: 0), actionName: "Typing")
        log.record(BufferOperation(kind: .insert(content: "b", at: 1)))
        try! buffer.insert("b", at: 1)
        log.endUndoGroup(selectionAfter: NSRange(location: 2, length: 0))

        log.endUndoGroup(selectionAfter: NSRange(location: 2, length: 0))

        XCTAssertEqual(log.history[0].actionName, "Typing")
    }

    func testActionName_NotOverwrittenWhenParentAlreadyHasOne() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0), actionName: "Paste")
        log.record(BufferOperation(kind: .insert(content: "a", at: 0)))
        try! buffer.insert("a", at: 0)

        log.beginUndoGroup(selectionBefore: NSRange(location: 1, length: 0), actionName: "Typing")
        log.record(BufferOperation(kind: .insert(content: "b", at: 1)))
        try! buffer.insert("b", at: 1)
        log.endUndoGroup(selectionAfter: NSRange(location: 2, length: 0))

        log.endUndoGroup(selectionAfter: NSRange(location: 2, length: 0))

        XCTAssertEqual(log.history[0].actionName, "Paste")
    }

    func testRedoTailTruncated_OnNewEditAfterUndo() {
        let buffer = MutableStringBuffer("abc")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "x", at: 0)))
        try! buffer.insert("x", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 1, length: 0))

        _ = log.undo(on: buffer)
        XCTAssertTrue(log.canRedo)

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "y", at: 0)))
        try! buffer.insert("y", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 1, length: 0))

        XCTAssertFalse(log.canRedo)
        XCTAssertEqual(log.history.count, 1)
        XCTAssertEqual(buffer.content, "yabc")
    }

    func testCanUndoAndCanRedo_StateTransitions() {
        let buffer = MutableStringBuffer("hi")
        var log = OperationLog()

        XCTAssertFalse(log.canUndo)
        XCTAssertFalse(log.canRedo)

        log.beginUndoGroup(selectionBefore: NSRange(location: 2, length: 0))
        log.record(BufferOperation(kind: .delete(range: NSRange(location: 0, length: 2), deletedContent: "hi")))
        try! buffer.delete(in: NSRange(location: 0, length: 2))
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 0))

        XCTAssertTrue(log.canUndo)
        XCTAssertFalse(log.canRedo)

        _ = log.undo(on: buffer)

        XCTAssertFalse(log.canUndo)
        XCTAssertTrue(log.canRedo)

        _ = log.redo(on: buffer)

        XCTAssertTrue(log.canUndo)
        XCTAssertFalse(log.canRedo)
    }

    func testSelectionBefore_RestoredOnUndo() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        let selectionBefore = NSRange(location: 2, length: 3)
        log.beginUndoGroup(selectionBefore: selectionBefore)
        log.record(BufferOperation(kind: .replace(range: NSRange(location: 2, length: 3), oldContent: "llo", newContent: "LP")))
        try! buffer.replace(range: NSRange(location: 2, length: 3), with: "LP")
        log.endUndoGroup(selectionAfter: NSRange(location: 2, length: 2))

        let restored = log.undo(on: buffer)
        XCTAssertEqual(restored, selectionBefore)
    }

    func testSelectionAfter_RestoredOnRedo() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        let selectionAfter = NSRange(location: 2, length: 2)
        log.beginUndoGroup(selectionBefore: NSRange(location: 2, length: 3))
        log.record(BufferOperation(kind: .replace(range: NSRange(location: 2, length: 3), oldContent: "llo", newContent: "LP")))
        try! buffer.replace(range: NSRange(location: 2, length: 3), with: "LP")
        log.endUndoGroup(selectionAfter: selectionAfter)

        _ = log.undo(on: buffer)
        let restored = log.redo(on: buffer)
        XCTAssertEqual(restored, selectionAfter)
    }

    func testUndoThenRedo_IsIdentity() {
        let buffer = MutableStringBuffer("hello world")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 5))
        log.record(BufferOperation(kind: .replace(range: NSRange(location: 0, length: 5), oldContent: "hello", newContent: "howdy")))
        try! buffer.replace(range: NSRange(location: 0, length: 5), with: "howdy")
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 5))

        let contentAfterEdit = buffer.content

        _ = log.undo(on: buffer)
        _ = log.redo(on: buffer)

        XCTAssertEqual(buffer.content, contentAfterEdit)
    }

    func testRedoThenUndo_IsIdentity() {
        let buffer = MutableStringBuffer("hello world")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 5))
        log.record(BufferOperation(kind: .replace(range: NSRange(location: 0, length: 5), oldContent: "hello", newContent: "howdy")))
        try! buffer.replace(range: NSRange(location: 0, length: 5), with: "howdy")
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 5))

        _ = log.undo(on: buffer)
        let contentAfterUndo = buffer.content

        _ = log.redo(on: buffer)
        _ = log.undo(on: buffer)

        XCTAssertEqual(buffer.content, contentAfterUndo)
    }

    func testValueTypeCopyIndependence() {
        let buffer = MutableStringBuffer("hi")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "!", at: 2)))
        try! buffer.insert("!", at: 2)
        log.endUndoGroup(selectionAfter: NSRange(location: 3, length: 0))

        var logCopy = log
        _ = logCopy.undo(on: buffer)

        XCTAssertTrue(log.canUndo)
        XCTAssertFalse(logCopy.canUndo)
    }

    func testUndoActionNameAndRedoActionName() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        XCTAssertNil(log.undoActionName)
        XCTAssertNil(log.redoActionName)

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0), actionName: "Typing")
        log.record(BufferOperation(kind: .insert(content: "a", at: 0)))
        try! buffer.insert("a", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 1, length: 0))

        XCTAssertEqual(log.undoActionName, "Typing")
        XCTAssertNil(log.redoActionName)

        _ = log.undo(on: buffer)

        XCTAssertNil(log.undoActionName)
        XCTAssertEqual(log.redoActionName, "Typing")
    }

    func testActionNameAtIndex_BoundsChecking() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0), actionName: "First")
        log.record(BufferOperation(kind: .insert(content: "a", at: 0)))
        try! buffer.insert("a", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 1, length: 0))

        XCTAssertEqual(log.actionName(at: 0), "First")
        XCTAssertNil(log.actionName(at: 1))
        XCTAssertNil(log.actionName(at: -1))
    }

    func testUndo_ReturnsNilWhenNothingToUndo() {
        let buffer = MutableStringBuffer("hi")
        var log = OperationLog()

        let result = log.undo(on: buffer)
        XCTAssertNil(result)
    }

    func testRedo_ReturnsNilWhenNothingToRedo() {
        let buffer = MutableStringBuffer("hi")
        var log = OperationLog()

        let result = log.redo(on: buffer)
        XCTAssertNil(result)
    }

    func testUndoableCount_ReflectsCursorPosition() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        XCTAssertEqual(log.undoableCount, 0)

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "a", at: 0)))
        try! buffer.insert("a", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 1, length: 0))

        XCTAssertEqual(log.undoableCount, 1)

        log.beginUndoGroup(selectionBefore: NSRange(location: 1, length: 0))
        log.record(BufferOperation(kind: .insert(content: "b", at: 1)))
        try! buffer.insert("b", at: 1)
        log.endUndoGroup(selectionAfter: NSRange(location: 2, length: 0))

        XCTAssertEqual(log.undoableCount, 2)

        _ = log.undo(on: buffer)
        XCTAssertEqual(log.undoableCount, 1)

        _ = log.undo(on: buffer)
        XCTAssertEqual(log.undoableCount, 0)
    }

    func testPopUndo_ReturnsNilWhenEmpty() {
        var log = OperationLog()
        XCTAssertNil(log.popUndo())
    }

    func testPopRedo_ReturnsNilWhenEmpty() {
        var log = OperationLog()
        XCTAssertNil(log.popRedo())
    }

    func testPopUndo_ReturnsGroupAndMovesCursorBack() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "hi ", at: 0)))
        try! buffer.insert("hi ", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 3, length: 0))

        let group = log.popUndo()

        XCTAssertNotNil(group)
        XCTAssertEqual(group?.selectionBefore, NSRange(location: 0, length: 0))
        XCTAssertEqual(group?.operations.count, 1)
        XCTAssertFalse(log.canUndo)
        XCTAssertTrue(log.canRedo)
    }

    func testPopRedo_ReturnsGroupAndMovesCursorForward() {
        let buffer = MutableStringBuffer("hello")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0))
        log.record(BufferOperation(kind: .insert(content: "hi ", at: 0)))
        try! buffer.insert("hi ", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 3, length: 0))

        _ = log.popUndo()
        let group = log.popRedo()

        XCTAssertNotNil(group)
        XCTAssertEqual(group?.selectionAfter, NSRange(location: 3, length: 0))
        XCTAssertEqual(group?.operations.count, 1)
        XCTAssertTrue(log.canUndo)
        XCTAssertFalse(log.canRedo)
    }

    func testPopUndo_PopRedo_RoundTrip() {
        let buffer = MutableStringBuffer("")
        var log = OperationLog()

        log.beginUndoGroup(selectionBefore: NSRange(location: 0, length: 0), actionName: "Insert")
        log.record(BufferOperation(kind: .insert(content: "abc", at: 0)))
        try! buffer.insert("abc", at: 0)
        log.endUndoGroup(selectionAfter: NSRange(location: 3, length: 0))

        log.beginUndoGroup(selectionBefore: NSRange(location: 3, length: 0), actionName: "Delete")
        log.record(BufferOperation(kind: .delete(range: NSRange(location: 0, length: 3), deletedContent: "abc")))
        try! buffer.delete(in: NSRange(location: 0, length: 3))
        log.endUndoGroup(selectionAfter: NSRange(location: 0, length: 0))

        let group2 = log.popUndo()
        XCTAssertEqual(group2?.actionName, "Delete")
        XCTAssertEqual(log.undoableCount, 1)

        let group1 = log.popUndo()
        XCTAssertEqual(group1?.actionName, "Insert")
        XCTAssertEqual(log.undoableCount, 0)

        let redo1 = log.popRedo()
        XCTAssertEqual(redo1?.actionName, "Insert")
        XCTAssertEqual(log.undoableCount, 1)
    }
}
