import XCTest
import TextBuffer

@MainActor
final class SendableRopeBufferConversionTests: XCTestCase {

    // MARK: - init(copying:)

    func testInitCopyingFromMutableStringBuffer() {
        let msb = MutableStringBuffer("hello world")
        msb.selectedRange = NSRange(location: 5, length: 6)

        let srb = SendableRopeBuffer(copying: msb)

        XCTAssertEqual(srb.content, "hello world")
        XCTAssertEqual(srb.selectedRange, NSRange(location: 5, length: 6))
        XCTAssertFalse(srb.log.canUndo)
    }

    func testInitCopyingFromRopeBuffer() {
        let rb = RopeBuffer("test content")
        rb.selectedRange = NSRange(location: 4, length: 0)

        let srb = SendableRopeBuffer(copying: rb)

        XCTAssertEqual(srb.content, "test content")
        XCTAssertEqual(srb.selectedRange, NSRange(location: 4, length: 0))
    }

    // MARK: - init(from:) TransferableUndoable

    func testInitFromTransferableUndoablePreservesLog() throws {
        let tu = TransferableUndoable(MutableStringBuffer("hello"))
        try tu.insert("X", at: 0)
        try tu.insert("Y", at: 1)

        let srb = SendableRopeBuffer(from: tu)

        XCTAssertEqual(srb.content, "XYhello")
        XCTAssertEqual(srb.log.undoableCount, 2)
        XCTAssertTrue(srb.log.canUndo)
    }

    // MARK: - toRopeBuffer()

    func testToRopeBufferPreservesContentAndSelection() {
        var srb = SendableRopeBuffer("hello world")
        srb.selectedRange = NSRange(location: 6, length: 5)

        let rb = srb.toRopeBuffer()

        XCTAssertEqual(rb.content, "hello world")
        XCTAssertEqual(rb.selectedRange, NSRange(location: 6, length: 5))
    }

    // MARK: - toTransferableUndoable()

    func testToTransferableUndoablePreservesContentSelectionAndLog() throws {
        var srb = SendableRopeBuffer("hello")
        try srb.insert("X", at: 0)
        srb.selectedRange = NSRange(location: 1, length: 0)

        let tu = srb.toTransferableUndoable()

        XCTAssertEqual(tu.content, "Xhello")
        XCTAssertEqual(tu.selectedRange, NSRange(location: 1, length: 0))
        XCTAssertTrue(tu.canUndo)

        tu.undo()
        XCTAssertEqual(tu.content, "hello")
    }

    // MARK: - sendableSnapshot()

    func testSendableSnapshotFromTransferableUndoable() throws {
        let tu = TransferableUndoable(RopeBuffer("hello"))
        try tu.insert("X", at: 0)

        let snapshot = tu.sendableSnapshot()

        XCTAssertEqual(snapshot.content, "Xhello")
        XCTAssertEqual(snapshot.selectedRange, tu.selectedRange)
        XCTAssertEqual(snapshot.log.undoableCount, tu.log.undoableCount)
    }

    func testSendableSnapshotFromMutableStringBufferBase() throws {
        let tu = TransferableUndoable(MutableStringBuffer("hello"))
        try tu.insert("X", at: 0)

        let snapshot = tu.sendableSnapshot()

        XCTAssertEqual(snapshot.content, "Xhello")
        XCTAssertTrue(snapshot.log.canUndo)
    }

    // MARK: - represent(_:)

    func testRepresentReplacesContent() throws {
        let tu = TransferableUndoable(RopeBuffer("original"))

        var snapshot = SendableRopeBuffer("modified")
        snapshot.selectedRange = NSRange(location: 3, length: 0)
        try snapshot.insert("X", at: 0)

        tu.represent(snapshot)

        XCTAssertEqual(tu.content, "Xmodified")
        XCTAssertEqual(tu.selectedRange, snapshot.selectedRange)
        XCTAssertEqual(tu.log.undoableCount, snapshot.log.undoableCount)
    }

    func testRepresentAllowsUndoAfterwards() throws {
        let tu = TransferableUndoable(RopeBuffer("original"))

        var snapshot = SendableRopeBuffer("hello")
        try snapshot.insert("X", at: 0)

        tu.represent(snapshot)

        XCTAssertEqual(tu.content, "Xhello")
        tu.undo()
        XCTAssertEqual(tu.content, "hello")
    }

    // MARK: - Round trip

    func testRoundTripSnapshotMutateRepresentUndo() throws {
        let tu = TransferableUndoable(RopeBuffer("hello world"))
        try tu.replace(range: NSRange(location: 0, length: 5), with: "howdy")
        XCTAssertEqual(tu.content, "howdy world")

        var snapshot = tu.sendableSnapshot()
        try snapshot.replace(range: NSRange(location: 6, length: 5), with: "earth")
        XCTAssertEqual(snapshot.content, "howdy earth")

        tu.represent(snapshot)
        XCTAssertEqual(tu.content, "howdy earth")

        tu.undo()
        XCTAssertEqual(tu.content, "howdy world")

        tu.undo()
        XCTAssertEqual(tu.content, "hello world")
    }
}
