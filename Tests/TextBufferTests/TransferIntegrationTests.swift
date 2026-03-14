import XCTest
import Foundation
import TextBuffer
import TextBufferTesting

@MainActor
final class TransferIntegrationTests: XCTestCase {
    func testTransferOutPreservesUndo() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        try! buffer.insert("Hello", at: 0)
        try! buffer.insert(" World", at: 5)
        let snap = buffer.snapshot()

        buffer.undo()
        XCTAssertEqual(buffer.content, "Hello")
        XCTAssertEqual(snap.content, "Hello World")
    }

    func testTransferInPreservesUndo() {
        let source = TransferableUndoable(MutableStringBuffer(""))
        try! source.insert("A", at: 0)
        try! source.insert("B", at: 1)

        let receiver = TransferableUndoable(MutableStringBuffer(""))
        receiver.represent(source)

        receiver.undo()
        XCTAssertEqual(receiver.content, "A")
        receiver.undo()
        XCTAssertEqual(receiver.content, "")
    }

    func testTransitivity() {
        let a = TransferableUndoable(MutableStringBuffer(""))
        try! a.insert("Hello", at: 0)

        let b = TransferableUndoable(MutableStringBuffer(""))
        b.represent(a)
        try! b.insert(" World", at: 5)

        let c = b.snapshot()

        try! a.insert("!", at: 5)
        b.undo()

        XCTAssertEqual(a.content, "Hello!")
        XCTAssertEqual(b.content, "Hello")
        XCTAssertEqual(c.content, "Hello World")

        c.undo()
        XCTAssertEqual(c.content, "Hello")
        c.undo()
        XCTAssertEqual(c.content, "")
    }

    func testSnapshotDuringActivePuppetBridge() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        try! buffer.insert("Hello", at: 0)
        let puppet = buffer.enableSystemUndoIntegration()

        let snap = buffer.snapshot()

        XCTAssertEqual(snap.content, "Hello")
        XCTAssertTrue(snap.canUndo)
        XCTAssertTrue(puppet.canUndo)

        (puppet as! PuppetUndoManager).undo()
        XCTAssertEqual(buffer.content, "")
        XCTAssertEqual(snap.content, "Hello")
    }

    func testRepresentDiscardsAllPreviousHistory() {
        let receiver = TransferableUndoable(MutableStringBuffer(""))
        for i in 0..<5 {
            try! receiver.insert(String(i), at: i)
        }
        XCTAssertEqual(receiver.log.undoableCount, 5)

        let source = TransferableUndoable(MutableStringBuffer(""))
        try! source.insert("A", at: 0)
        try! source.insert("B", at: 1)

        receiver.represent(source)
        XCTAssertEqual(receiver.log.undoableCount, 2)

        receiver.undo()
        receiver.undo()
        XCTAssertFalse(receiver.canUndo)
        XCTAssertEqual(receiver.content, "")
    }
}
