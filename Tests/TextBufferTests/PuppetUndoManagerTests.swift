import XCTest
import Foundation
@testable import TextBuffer

@MainActor
final class PuppetUndoManagerTests: XCTestCase {
    func testCanUndoCanRedoReflectLogState() throws {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        let puppet = buffer.enableSystemUndoIntegration() as! PuppetUndoManager
        XCTAssertFalse(puppet.canUndo)
        XCTAssertFalse(puppet.canRedo)
        try buffer.insert("A", at: 0)
        XCTAssertTrue(puppet.canUndo)
        XCTAssertFalse(puppet.canRedo)
        buffer.undo()
        XCTAssertFalse(puppet.canUndo)
        XCTAssertTrue(puppet.canRedo)
        try buffer.insert("B", at: 0)
        XCTAssertFalse(puppet.canRedo)
    }

    func testPuppetUndoTriggersLogUndo() throws {
        let buffer = TransferableUndoable(MutableStringBuffer("hello"))
        let puppet = buffer.enableSystemUndoIntegration() as! PuppetUndoManager
        try buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.content, "Xhello")
        puppet.undo()
        XCTAssertEqual(buffer.content, "hello")
    }

    func testPuppetRedoTriggersLogRedo() throws {
        let buffer = TransferableUndoable(MutableStringBuffer("hello"))
        let puppet = buffer.enableSystemUndoIntegration() as! PuppetUndoManager
        try buffer.insert("X", at: 0)
        puppet.undo()
        puppet.redo()
        XCTAssertEqual(buffer.content, "Xhello")
    }

    func testUndoActionNameRedoActionNameReflectLog() throws {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        let puppet = buffer.enableSystemUndoIntegration() as! PuppetUndoManager
        XCTAssertEqual(puppet.undoActionName, "")
        XCTAssertEqual(puppet.redoActionName, "")
        buffer.undoGrouping(actionName: "Typing") {
            try! buffer.insert("A", at: 0)
        }
        XCTAssertEqual(puppet.undoActionName, "Typing")
        XCTAssertEqual(puppet.redoActionName, "")
        buffer.undo()
        XCTAssertEqual(puppet.undoActionName, "")
        XCTAssertEqual(puppet.redoActionName, "Typing")
    }

    func testRegisterUndoWithHandlerDoesNotChangeCanUndo() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        let puppet = buffer.enableSystemUndoIntegration()
        puppet.registerUndo(withTarget: buffer) { _ in }
        XCTAssertFalse(puppet.canUndo)
    }

    func testRegisterUndoWithSelectorDoesNotChangeCanUndo() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        let puppet = buffer.enableSystemUndoIntegration()
        puppet.registerUndo(withTarget: buffer, selector: #selector(NSObject.doesNotRecognizeSelector(_:)), object: nil)
        XCTAssertFalse(puppet.canUndo)
    }

    func testGroupsByEventIsFalse() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        let puppet = buffer.enableSystemUndoIntegration()
        XCTAssertFalse(puppet.groupsByEvent)
    }

    func testEnableSystemUndoIntegrationReturnsSameInstance() {
        let buffer = TransferableUndoable(MutableStringBuffer(""))
        let a = buffer.enableSystemUndoIntegration()
        let b = buffer.enableSystemUndoIntegration()
        XCTAssertTrue(a === b)
    }

    func testSafeDegradationAfterOwnerDeallocation() throws {
        var buffer: TransferableUndoable<MutableStringBuffer>? = TransferableUndoable(MutableStringBuffer("hello"))
        try buffer!.insert("X", at: 0)
        let puppet = buffer!.enableSystemUndoIntegration() as! PuppetUndoManager
        buffer = nil
        XCTAssertFalse(puppet.canUndo)
        XCTAssertFalse(puppet.canRedo)
        XCTAssertEqual(puppet.undoActionName, "")
        XCTAssertEqual(puppet.redoActionName, "")
        puppet.undo()
        puppet.redo()
    }
}
