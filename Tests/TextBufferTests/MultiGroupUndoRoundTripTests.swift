import Foundation
import Testing
import TextBuffer

@MainActor
private func makeThreeGroupSource() -> EditingBuffer {
    let source = TransferableUndoable(RopeBuffer(""))
    source.undoGrouping {
        for (offset, character) in "hello".enumerated() {
            try! source.insert(String(character), at: offset)
        }
    }
    source.undoGrouping {
        for (offset, character) in " world".enumerated() {
            try! source.insert(String(character), at: 5 + offset)
        }
    }
    source.selectedRange = NSRange(location: 0, length: 5)
    source.undoGrouping {
        try! source.replace(range: NSRange(location: 0, length: 5), with: "howdy")
    }
    return source
}

@MainActor
@Suite struct MultiGroupUndoRoundTripTests {
    @Test func `multi-group undo history survives a sendable snapshot into a fresh in-memory buffer`() {
        let source = makeThreeGroupSource()

        var transferred: InMemoryBuffer = source.sendableSnapshot()

        #expect(transferred.content == "howdy world")
        #expect(transferred.selectedRange == source.selectedRange)
        #expect(transferred.log.undoableCount == 3)

        #expect(transferred.undo() == NSRange(location: 0, length: 5))
        #expect(transferred.content == "hello world")

        #expect(transferred.undo() == NSRange(location: 5, length: 0))
        #expect(transferred.content == "hello")

        #expect(transferred.undo() == NSRange(location: 0, length: 0))
        #expect(transferred.content == "")

        #expect(transferred.redo() == NSRange(location: 5, length: 0))
        #expect(transferred.content == "hello")

        #expect(transferred.redo() == NSRange(location: 11, length: 0))
        #expect(transferred.content == "hello world")

        #expect(transferred.redo() == NSRange(location: 5, length: 0))
        #expect(transferred.content == "howdy world")
        #expect(transferred.canRedo == false)
    }

    @Test func `multi-group undo history survives represent into a fresh editing buffer`() {
        let source = makeThreeGroupSource()
        let snapshot = source.sendableSnapshot()

        let receiver = TransferableUndoable(RopeBuffer(""))
        receiver.represent(snapshot)

        #expect(receiver.content == "howdy world")
        #expect(receiver.selectedRange == source.selectedRange)

        receiver.undo()
        #expect(receiver.content == "hello world")
        #expect(receiver.selectedRange == NSRange(location: 0, length: 5))

        receiver.undo()
        #expect(receiver.content == "hello")
        #expect(receiver.selectedRange == NSRange(location: 5, length: 0))

        receiver.undo()
        #expect(receiver.content == "")
        #expect(receiver.selectedRange == NSRange(location: 0, length: 0))
        #expect(receiver.canUndo == false)

        receiver.redo()
        #expect(receiver.content == "hello")
        #expect(receiver.selectedRange == NSRange(location: 5, length: 0))

        receiver.redo()
        #expect(receiver.content == "hello world")
        #expect(receiver.selectedRange == NSRange(location: 11, length: 0))

        receiver.redo()
        #expect(receiver.content == "howdy world")
        #expect(receiver.selectedRange == NSRange(location: 5, length: 0))
        #expect(receiver.canRedo == false)
    }

    @Test func `the transferred log is identical and every group keeps selectionAfter for redo`() {
        let source = makeThreeGroupSource()
        let snapshot = source.sendableSnapshot()

        let receiver = TransferableUndoable(RopeBuffer(""))
        receiver.represent(snapshot)

        #expect(receiver.log == source.log)
        #expect(receiver.log.history.count == 3)
        #expect(receiver.log.history.allSatisfy { $0.selectionAfter != nil })
        #expect(receiver.log.history.map(\.selectionAfter) == [
            NSRange(location: 5, length: 0),
            NSRange(location: 11, length: 0),
            NSRange(location: 5, length: 0),
        ])
    }
}
