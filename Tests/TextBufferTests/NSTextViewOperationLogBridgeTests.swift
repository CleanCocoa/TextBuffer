#if os(macOS)
import AppKit
import Testing
import TextBuffer

@MainActor
private func makeBridgedTextView(_ string: String = "") -> (textView: NSTextView, bridge: NSTextViewOperationLogBridge) {
    let textView = NSTextView(usingTextLayoutManager: false)
    textView.string = string
    let bridge = NSTextViewOperationLogBridge(textView: textView)
    return (textView, bridge)
}

@MainActor
private func type(
    _ replacement: String,
    replacing affectedRange: NSRange,
    in textView: NSTextView,
    forwardingTo bridge: NSTextViewOperationLogBridge
) {
    bridge.shouldChangeText(in: affectedRange, replacementString: replacement)
    textView.insertText(replacement, replacementRange: affectedRange)
    bridge.textDidChange()
}

@Suite struct NSTextViewOperationLogBridgeTests {
    @MainActor
    @Suite struct EditMirroring {
        @Test func `typing characters appends matching insert operations`() {
            let (textView, bridge) = makeBridgedTextView()

            type("a", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            type("b", replacing: NSRange(location: 1, length: 0), in: textView, forwardingTo: bridge)

            #expect(textView.string == "ab")
            #expect(bridge.log.history.map(\.operations) == [
                [BufferOperation(kind: .insert(content: "a", at: 0))],
                [BufferOperation(kind: .insert(content: "b", at: 1))],
            ])
        }

        @Test func `mirrored groups capture the selection before and after the edit`() {
            let (textView, bridge) = makeBridgedTextView()

            type("a", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)

            #expect(bridge.log.history.map(\.selectionBefore) == [NSRange(location: 0, length: 0)])
            #expect(bridge.log.history.map(\.selectionAfter) == [NSRange(location: 1, length: 0)])
        }

        @Test func `deleting text appends a delete operation preserving the removed content`() {
            let (textView, bridge) = makeBridgedTextView("abc")

            type("", replacing: NSRange(location: 2, length: 1), in: textView, forwardingTo: bridge)

            #expect(textView.string == "ab")
            #expect(bridge.log.history.map(\.operations) == [
                [BufferOperation(kind: .delete(range: NSRange(location: 2, length: 1), deletedContent: "c"))],
            ])
        }

        @Test func `replacing a selection appends a replace operation with old and new content`() {
            let (textView, bridge) = makeBridgedTextView("hello world")
            textView.setSelectedRange(NSRange(location: 0, length: 5))

            type("goodbye", replacing: NSRange(location: 0, length: 5), in: textView, forwardingTo: bridge)

            #expect(textView.string == "goodbye world")
            #expect(bridge.log.history.map(\.operations) == [
                [BufferOperation(kind: .replace(range: NSRange(location: 0, length: 5), oldContent: "hello", newContent: "goodbye"))],
            ])
        }

        @Test func `an attribute-only change with a nil replacement string records nothing`() {
            let (textView, bridge) = makeBridgedTextView("abc")

            bridge.shouldChangeText(in: NSRange(location: 0, length: 3), replacementString: nil)
            bridge.textDidChange()

            #expect(textView.string == "abc")
            #expect(bridge.log.history.isEmpty)
        }
    }

    @MainActor
    @Suite struct UndoRedoRouting {
        @Test func `undo replays the last group onto the view restoring content and selection`() {
            let (textView, bridge) = makeBridgedTextView()
            type("a", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            type("b", replacing: NSRange(location: 1, length: 0), in: textView, forwardingTo: bridge)

            bridge.undo()

            #expect(textView.string == "a")
            #expect(textView.selectedRange == NSRange(location: 1, length: 0))
        }

        @Test func `undo restores the selection that preceded a replacement`() {
            let (textView, bridge) = makeBridgedTextView("hello world")
            textView.setSelectedRange(NSRange(location: 0, length: 5))
            type("goodbye", replacing: NSRange(location: 0, length: 5), in: textView, forwardingTo: bridge)

            bridge.undo()

            #expect(textView.string == "hello world")
            #expect(textView.selectedRange == NSRange(location: 0, length: 5))
        }

        @Test func `redo reapplies an undone group restoring content and selection`() {
            let (textView, bridge) = makeBridgedTextView()
            type("a", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            type("b", replacing: NSRange(location: 1, length: 0), in: textView, forwardingTo: bridge)
            bridge.undo()

            bridge.redo()

            #expect(textView.string == "ab")
            #expect(textView.selectedRange == NSRange(location: 2, length: 0))
        }

        @Test func `undo and redo without history leave the view untouched`() {
            let (textView, bridge) = makeBridgedTextView("abc")

            bridge.undo()
            bridge.redo()

            #expect(textView.string == "abc")
        }

        @Test func `the puppet undo manager routes AppKit undo and redo to the log`() {
            let (textView, bridge) = makeBridgedTextView()
            let undoManager = bridge.enableSystemUndoIntegration()
            #expect(undoManager.canUndo == false)

            type("a", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            #expect(undoManager.canUndo)

            undoManager.undo()
            #expect(textView.string == "")
            #expect(undoManager.canUndo == false)
            #expect(undoManager.canRedo)

            undoManager.redo()
            #expect(textView.string == "a")
            #expect(undoManager.canRedo == false)
        }

        @Test func `enabling system undo integration twice returns the same undo manager`() {
            let (_, bridge) = makeBridgedTextView()

            #expect(bridge.enableSystemUndoIntegration() === bridge.enableSystemUndoIntegration())
        }
    }
}
#endif
