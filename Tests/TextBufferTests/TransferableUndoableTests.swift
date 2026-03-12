import XCTest
import Foundation
import TextBuffer

@MainActor
final class TransferableUndoableTests: XCTestCase {
    func `test content delegates to base`() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(buffer.content, "hello")
    }

    func `test range delegates to base`() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(buffer.range, NSRange(location: 0, length: 5))
    }

    func `test content in subrange delegates to base`() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(try buffer.content(in: NSRange(location: 1, length: 3)), "ell")
    }

    func `test selectedRange get delegates to base`() {
        let base = MutableStringBuffer("hello")
        base.selectedRange = NSRange(location: 2, length: 2)
        let buffer = TransferableUndoable(base)
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 2, length: 2))
    }

    func `test selectedRange set delegates to base`() {
        let base = MutableStringBuffer("hello")
        let buffer = TransferableUndoable(base)
        buffer.selectedRange = NSRange(location: 1, length: 3)
        XCTAssertEqual(base.selectedRange, NSRange(location: 1, length: 3))
    }

    func `test insert makes canUndo true`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        XCTAssertTrue(buffer.canUndo)
    }

    func `test delete makes canUndo true`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.delete(in: NSRange(location: 0, length: 1))
        XCTAssertTrue(buffer.canUndo)
    }

    func `test replace makes canUndo true`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.replace(range: NSRange(location: 0, length: 1), with: "Z")
        XCTAssertTrue(buffer.canUndo)
    }

    func `test auto-grouping wraps standalone mutation`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.log.undoableCount, 1)
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func `test no auto-grouping inside undoGrouping`() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        buffer.undoGrouping {
            try! buffer.insert("A", at: 0)
            try! buffer.insert("B", at: 1)
        }
        XCTAssertEqual(buffer.log.undoableCount, 1)
    }

    func `test undo after insert restores content`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.content, "Xabc")
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func `test undo after insert restores selection`() {
        let base = MutableStringBuffer("abc")
        base.selectedRange = NSRange(location: 1, length: 0)
        let buffer = TransferableUndoable(base)
        let selectionBefore = base.selectedRange
        try! buffer.insert("X", at: 0)
        buffer.undo()
        XCTAssertEqual(buffer.selectedRange, selectionBefore)
    }

    func `test undo after delete restores content`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.delete(in: NSRange(location: 0, length: 1))
        XCTAssertEqual(buffer.content, "bc")
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func `test undo after replace restores content`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.replace(range: NSRange(location: 0, length: 3), with: "XYZ")
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func `test redo after undo restores content`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.insert("X", at: 0)
        buffer.undo()
        buffer.redo()
        XCTAssertEqual(buffer.content, "Xabc")
    }

    func `test undo then redo is identity`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        try! buffer.replace(range: NSRange(location: 0, length: 3), with: "XYZ")
        let afterEdit = buffer.content
        let selectionAfterEdit = buffer.selectedRange
        buffer.undo()
        buffer.redo()
        XCTAssertEqual(buffer.content, afterEdit)
        XCTAssertEqual(buffer.selectedRange, selectionAfterEdit)
    }

    func `test redo tail truncated after new edit`() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        try! buffer.insert("A", at: 0)
        buffer.undo()
        try! buffer.insert("B", at: 0)
        XCTAssertFalse(buffer.canRedo)
        buffer.redo()
        XCTAssertEqual(buffer.content, "B")
    }

    func `test single group two inserts single undo reverses both`() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        buffer.undoGrouping {
            try! buffer.insert("A", at: 0)
            try! buffer.insert("B", at: 1)
        }
        XCTAssertEqual(buffer.content, "AB")
        buffer.undo()
        XCTAssertEqual(buffer.content, "")
    }

    func `test nested grouping inner merges into outer`() {
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

    func `test action name propagation`() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        buffer.undoGrouping(actionName: "MyAction") {
            try! buffer.insert("A", at: 0)
        }
        XCTAssertEqual(buffer.log.undoActionName, "MyAction")
    }

    func `test undo when nothing to undo is noop`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        buffer.undo()
        XCTAssertEqual(buffer.content, "abc")
    }

    func `test redo when nothing to redo is noop`() {
        let buffer = TransferableUndoable(MutableStringBuffer("abc"))
        buffer.redo()
        XCTAssertEqual(buffer.content, "abc")
    }
}
