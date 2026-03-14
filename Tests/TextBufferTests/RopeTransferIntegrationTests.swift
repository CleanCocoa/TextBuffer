import XCTest
import Foundation
import TextBuffer
import TextBufferTesting

@MainActor
final class RopeTransferIntegrationTests: XCTestCase {
    func testUndoRedoOnRopeBuffer() {
        let buffer = TransferableUndoable(RopeBuffer("hello"))
        try! buffer.insert(" world", at: 5)
        XCTAssertEqual(buffer.content, "hello world")

        buffer.undo()
        XCTAssertEqual(buffer.content, "hello")

        buffer.redo()
        XCTAssertEqual(buffer.content, "hello world")
    }

    func testGroupedUndoOnRopeBuffer() {
        let buffer = TransferableUndoable(RopeBuffer(""))
        buffer.undoGrouping {
            try! buffer.insert("A", at: 0)
            try! buffer.insert("B", at: 1)
        }
        XCTAssertEqual(buffer.content, "AB")
        XCTAssertEqual(buffer.log.undoableCount, 1)

        buffer.undo()
        XCTAssertEqual(buffer.content, "")
    }

    func testSnapshotFromRopeBufferToMutableStringBuffer() {
        let buffer = TransferableUndoable(RopeBuffer("hello"))
        try! buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.content, "Xhello")

        let snap = buffer.snapshot()
        XCTAssertEqual(snap.content, "Xhello")
        XCTAssertTrue(snap.canUndo)

        snap.undo()
        XCTAssertEqual(snap.content, "hello")
    }

    func testRepresentFromMutableStringBufferIntoRopeBuffer() {
        let source = TransferableUndoable(MutableStringBuffer("data"))
        try! source.insert("!", at: 4)
        try! source.insert("?", at: 5)
        XCTAssertEqual(source.content, "data!?")

        let receiver = TransferableUndoable(RopeBuffer(""))
        receiver.represent(source)
        XCTAssertEqual(receiver.content, "data!?")

        receiver.undo()
        XCTAssertEqual(receiver.content, "data!")
        receiver.undo()
        XCTAssertEqual(receiver.content, "data")
    }

    func testSnapshotThenRepresentRoundTrip() {
        let rope = TransferableUndoable(RopeBuffer("base"))
        try! rope.insert("X", at: 4)
        XCTAssertEqual(rope.content, "baseX")

        let snap = rope.snapshot()
        try! snap.insert("Y", at: 5)
        XCTAssertEqual(snap.content, "baseXY")

        rope.represent(snap)
        XCTAssertEqual(rope.content, "baseXY")

        rope.undo()
        XCTAssertEqual(rope.content, "baseX")
        rope.undo()
        XCTAssertEqual(rope.content, "base")
    }

    func testSnapshotIndependence() {
        let rope = TransferableUndoable(RopeBuffer("original"))
        try! rope.insert("!", at: 8)
        let snap = rope.snapshot()

        try! rope.insert("?", at: 9)
        XCTAssertEqual(rope.content, "original!?")
        XCTAssertEqual(snap.content, "original!")

        try! snap.insert("Z", at: 0)
        XCTAssertEqual(snap.content, "Zoriginal!")
        XCTAssertEqual(rope.content, "original!?")
    }

    func testUndoEquivalenceAcrossBufferTypes() {
        let msb = TransferableUndoable(MutableStringBuffer("abc"))
        let rb = TransferableUndoable(RopeBuffer("abc"))

        try! msb.insert("X", at: 0)
        try! rb.insert("X", at: 0)
        XCTAssertEqual(msb.content, rb.content, "after insert")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after insert")

        try! msb.delete(in: NSRange(location: 1, length: 2))
        try! rb.delete(in: NSRange(location: 1, length: 2))
        XCTAssertEqual(msb.content, rb.content, "after delete")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after delete")

        try! msb.replace(range: NSRange(location: 0, length: 1), with: "YZ")
        try! rb.replace(range: NSRange(location: 0, length: 1), with: "YZ")
        XCTAssertEqual(msb.content, rb.content, "after replace")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after replace")

        msb.undo()
        rb.undo()
        XCTAssertEqual(msb.content, rb.content, "after undo")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after undo")

        msb.redo()
        rb.redo()
        XCTAssertEqual(msb.content, rb.content, "after redo")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after redo")
    }
}
