import XCTest
import Foundation
import TextBuffer
import TextBufferTesting

class TransferIntegrationTests: XCTestCase {
#if false
    func `testTransferOutPreservesUndo`() {
        let buffer = TransferableUndoable(MutableStringBuffer("hello"))
        try? buffer.insert(" world", at: 5)
        let snapshot = buffer.snapshot()
        let restored = TransferableUndoable(MutableStringBuffer(""))
        try? restored.represent(snapshot)
        restored.undo()
        XCTAssertEqual(restored.content, "hello")
    }

    func `testTransferInPreservesUndo`() {
        let source = TransferableUndoable(MutableStringBuffer(""))
        try? source.insert("abc", at: 0)
        try? source.insert("def", at: 3)
        let snapshot = source.snapshot()
        let target = TransferableUndoable(MutableStringBuffer(""))
        try? target.represent(snapshot)
        target.undo()
        XCTAssertEqual(target.content, "abc")
        target.undo()
        XCTAssertEqual(target.content, "")
    }

    func `testTransitivity`() {
        let initial = "start"
        let steps: [BufferStep] = [
            .insert(content: " middle", at: 5),
            .insert(content: " end", at: 12),
            .undo,
        ]
        assertUndoEquivalence(initial: initial, steps: steps)
    }
#endif
}
