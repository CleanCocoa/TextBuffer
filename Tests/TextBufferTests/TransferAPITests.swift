import XCTest
import Foundation
import TextBuffer

@MainActor
final class TransferAPITests: XCTestCase {
    func testSnapshotCopiesContentAndSelection() {
        let buffer = TransferableUndoable(MutableStringBuffer("Hello"))
        buffer.selectedRange = NSRange(location: 2, length: 3)
        let snap = buffer.snapshot()
        XCTAssertEqual(snap.content, "Hello")
        XCTAssertEqual(snap.selectedRange, NSRange(location: 2, length: 3))
    }

    func testSnapshotCopiesUndoHistory() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        try! buffer.insert("A", at: 0)
        try! buffer.insert("B", at: 1)
        let snap = buffer.snapshot()
        XCTAssertTrue(snap.canUndo)
        snap.undo()
        XCTAssertEqual(snap.content, "A")
    }

    func testMutatingSnapshotDoesNotAffectOriginal() {
        let buffer = TransferableUndoable(MutableStringBuffer("Hello"))
        try! buffer.insert("X", at: 0)
        let snap = buffer.snapshot()
        try! snap.insert("Y", at: 0)
        XCTAssertEqual(buffer.content, "XHello")
        XCTAssertEqual(snap.content, "YXHello")
    }

    func testMutatingOriginalDoesNotAffectSnapshot() {
        let buffer = TransferableUndoable(MutableStringBuffer("Hello"))
        try! buffer.insert("X", at: 0)
        let snap = buffer.snapshot()
        try! buffer.insert("Z", at: 0)
        XCTAssertEqual(snap.content, "XHello")
        XCTAssertEqual(buffer.content, "ZXHello")
    }

    func testRepresentReplacesContentAndSelection() {
        let receiver = TransferableUndoable(MutableStringBuffer("Old"))
        let source = TransferableUndoable(MutableStringBuffer("New"))
        source.selectedRange = NSRange(location: 1, length: 2)
        receiver.represent(source)
        XCTAssertEqual(receiver.content, "New")
        XCTAssertEqual(receiver.selectedRange, NSRange(location: 1, length: 2))
    }

    func testRepresentReplacesUndoHistory() {
        let receiver = TransferableUndoable(MutableStringBuffer(""))
        try! receiver.insert("Old", at: 0)

        let source = TransferableUndoable(MutableStringBuffer(""))
        try! source.insert("A", at: 0)
        try! source.insert("B", at: 1)

        receiver.represent(source)
        XCTAssertTrue(receiver.canUndo)
        receiver.undo()
        XCTAssertEqual(receiver.content, "A")
    }

    func testRepresentDiscardsReceiverUndoState() {
        let receiver = TransferableUndoable(MutableStringBuffer(""))
        try! receiver.insert("X", at: 0)
        try! receiver.insert("Y", at: 1)
        try! receiver.insert("Z", at: 2)

        let source = TransferableUndoable(MutableStringBuffer(""))
        try! source.insert("A", at: 0)

        receiver.represent(source)
        XCTAssertEqual(receiver.log.undoableCount, 1)
        receiver.undo()
        XCTAssertFalse(receiver.canUndo)
    }

    func testRepresentThenUndoThenRedoRoundTrip() {
        let source = TransferableUndoable(MutableStringBuffer(""))
        try! source.insert("Hello", at: 0)
        try! source.insert(" World", at: 5)

        let receiver = TransferableUndoable(MutableStringBuffer(""))
        receiver.represent(source)

        receiver.undo()
        XCTAssertEqual(receiver.content, "Hello")
        receiver.redo()
        XCTAssertEqual(receiver.content, "Hello World")
    }

    func testRepresentIndependenceReceiverUndoDoesNotAffectSource() {
        let source = TransferableUndoable(MutableStringBuffer(""))
        try! source.insert("AB", at: 0)

        let receiver = TransferableUndoable(MutableStringBuffer(""))
        receiver.represent(source)
        receiver.undo()

        XCTAssertEqual(source.content, "AB")
        XCTAssertTrue(source.canUndo)
    }

    func testRepresentIndependenceSourceMutationDoesNotAffectReceiver() {
        let source = TransferableUndoable(MutableStringBuffer(""))
        try! source.insert("AB", at: 0)

        let receiver = TransferableUndoable(MutableStringBuffer(""))
        receiver.represent(source)

        try! source.insert("C", at: 2)
        XCTAssertEqual(receiver.content, "AB")
    }
}
