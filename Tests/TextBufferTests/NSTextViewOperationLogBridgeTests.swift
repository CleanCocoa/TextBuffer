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

@MainActor
private func markText(
    _ markedText: String,
    replacing affectedRange: NSRange,
    in textView: NSTextView,
    forwardingTo bridge: NSTextViewOperationLogBridge
) {
    bridge.shouldChangeText(in: affectedRange, replacementString: markedText)
    textView.setMarkedText(
        markedText,
        selectedRange: NSRange(location: markedText.utf16.count, length: 0),
        replacementRange: affectedRange
    )
    bridge.textDidChange()
}

@MainActor
private final class ForwardingDelegate: NSObject, NSTextViewDelegate {
    let bridge: NSTextViewOperationLogBridge
    private(set) var textDidChangeCount = 0
    var onTextDidChange: (() -> Void)?

    init(bridge: NSTextViewOperationLogBridge) {
        self.bridge = bridge
    }

    func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
        bridge.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
        return true
    }

    func textDidChange(_ notification: Notification) {
        textDidChangeCount += 1
        bridge.textDidChange()
        onTextDidChange?()
    }
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

        @Test func `a multi-range edit that outruns the staged change resets history instead of recording a lie`() {
            let (textView, bridge) = makeBridgedTextView("aaa bbb aaa")
            type("!", replacing: NSRange(location: 11, length: 0), in: textView, forwardingTo: bridge)
            #expect(bridge.log.history.count == 1)

            bridge.shouldChangeText(in: NSRange(location: 8, length: 3), replacementString: "cc")
            bridge.shouldChangeText(in: NSRange(location: 0, length: 3), replacementString: "cc")
            textView.textStorage!.replaceCharacters(in: NSRange(location: 8, length: 3), with: "cc")
            textView.textStorage!.replaceCharacters(in: NSRange(location: 0, length: 3), with: "cc")
            bridge.textDidChange()

            #expect(textView.string == "cc bbb cc!")
            #expect(bridge.log.history.isEmpty)
            #expect(bridge.log.canUndo == false)
            #expect(bridge.log.canRedo == false)
        }

        @Test func `a zero-length edit with an empty replacement string records nothing`() {
            let (textView, bridge) = makeBridgedTextView("abc")

            bridge.shouldChangeText(in: NSRange(location: 1, length: 0), replacementString: "")
            bridge.textDidChange()

            #expect(textView.string == "abc")
            #expect(bridge.log.history.isEmpty)
        }

        @Test func `an attribute-only change with a nil replacement string records nothing`() {
            let (textView, bridge) = makeBridgedTextView("abc")

            bridge.shouldChangeText(in: NSRange(location: 0, length: 3), replacementString: nil)
            bridge.textDidChange()

            #expect(textView.string == "abc")
            #expect(bridge.log.history.isEmpty)
        }

        @Test func `an attribute-only change after a vetoed edit invalidates the stale staged change`() {
            let (textView, bridge) = makeBridgedTextView()
            type("a", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            #expect(bridge.log.history.count == 1)

            bridge.shouldChangeText(in: NSRange(location: 1, length: 0), replacementString: "x")
            bridge.shouldChangeText(in: NSRange(location: 0, length: 1), replacementString: nil)
            bridge.textDidChange()

            #expect(textView.string == "a")
            #expect(bridge.log.history.count == 1)
        }
    }

    @MainActor
    @Suite struct AttributeOnlyEdits {
        @Test func `a bold-style attribute pass through the view's change callbacks records nothing`() {
            let (textView, bridge) = makeBridgedTextView()
            let delegate = ForwardingDelegate(bridge: bridge)
            textView.delegate = delegate
            defer { withExtendedLifetime(delegate) {} }
            textView.insertText("abc", replacementRange: NSRange(location: 0, length: 0))
            let historyAfterTyping = bridge.log.history

            let boldRange = NSRange(location: 0, length: 3)
            if textView.shouldChangeText(in: boldRange, replacementString: nil) {
                textView.textStorage!.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: boldRange)
                textView.didChangeText()
            }

            #expect(textView.string == "abc")
            #expect(bridge.log.history == historyAfterTyping)
        }

        @Test func `a direct textStorage attribute edit leaves the log untouched and replayable`() {
            let (textView, bridge) = makeBridgedTextView()
            let delegate = ForwardingDelegate(bridge: bridge)
            textView.delegate = delegate
            defer { withExtendedLifetime(delegate) {} }
            textView.insertText("abc", replacementRange: NSRange(location: 0, length: 0))
            let historyAfterTyping = bridge.log.history

            textView.textStorage!.beginEditing()
            textView.textStorage!.addAttribute(.foregroundColor, value: NSColor.systemRed, range: NSRange(location: 1, length: 2))
            textView.textStorage!.endEditing()

            #expect(bridge.log.history == historyAfterTyping)

            bridge.undo()
            #expect(textView.string == "")

            bridge.redo()
            #expect(textView.string == "abc")
        }

        @Test func `an attribute pass between typing keeps later undo groups replayable`() {
            let (textView, bridge) = makeBridgedTextView()
            let delegate = ForwardingDelegate(bridge: bridge)
            textView.delegate = delegate
            defer { withExtendedLifetime(delegate) {} }
            textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))

            let range = NSRange(location: 0, length: 1)
            if textView.shouldChangeText(in: range, replacementString: nil) {
                textView.textStorage!.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: 12), range: range)
                textView.didChangeText()
            }
            textView.insertText("b", replacementRange: NSRange(location: 1, length: 0))

            #expect(textView.string == "ab")

            bridge.undo()
            #expect(textView.string == "a")

            bridge.undo()
            #expect(textView.string == "")
        }
    }

    @MainActor
    @Suite struct MarkedTextComposition {
        @Test func `composition intermediates record nothing while marked text is active`() {
            let (textView, bridge) = makeBridgedTextView()

            markText("に", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            markText("にほ", replacing: NSRange(location: 0, length: 1), in: textView, forwardingTo: bridge)
            markText("にほん", replacing: NSRange(location: 0, length: 2), in: textView, forwardingTo: bridge)

            #expect(textView.string == "にほん")
            #expect(textView.hasMarkedText())
            #expect(bridge.log.history.isEmpty)
        }

        @Test func `committing a composition records exactly one insert group`() {
            let (textView, bridge) = makeBridgedTextView()
            markText("に", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            markText("にほ", replacing: NSRange(location: 0, length: 1), in: textView, forwardingTo: bridge)

            type("日本", replacing: NSRange(location: 0, length: 2), in: textView, forwardingTo: bridge)

            #expect(textView.string == "日本")
            #expect(textView.hasMarkedText() == false)
            #expect(bridge.log.history.map(\.operations) == [
                [BufferOperation(kind: .insert(content: "日本", at: 0))],
            ])
            #expect(bridge.log.history.map(\.selectionBefore) == [NSRange(location: 0, length: 0)])
            #expect(bridge.log.history.map(\.selectionAfter) == [NSRange(location: 2, length: 0)])
        }

        @Test func `undo after a committed composition removes the whole composition`() {
            let (textView, bridge) = makeBridgedTextView("ab")
            textView.setSelectedRange(NSRange(location: 1, length: 0))
            markText("に", replacing: NSRange(location: 1, length: 0), in: textView, forwardingTo: bridge)
            type("日", replacing: NSRange(location: 1, length: 1), in: textView, forwardingTo: bridge)
            #expect(textView.string == "a日b")

            bridge.undo()

            #expect(textView.string == "ab")
            #expect(textView.selectedRange == NSRange(location: 1, length: 0))
        }

        @Test func `committing a composition over a selection records one replace group`() {
            let (textView, bridge) = makeBridgedTextView("hello")
            textView.setSelectedRange(NSRange(location: 0, length: 5))
            markText("に", replacing: NSRange(location: 0, length: 5), in: textView, forwardingTo: bridge)

            type("日本", replacing: NSRange(location: 0, length: 1), in: textView, forwardingTo: bridge)

            #expect(textView.string == "日本")
            #expect(bridge.log.history.map(\.operations) == [
                [BufferOperation(kind: .replace(range: NSRange(location: 0, length: 5), oldContent: "hello", newContent: "日本"))],
            ])

            bridge.undo()

            #expect(textView.string == "hello")
            #expect(textView.selectedRange == NSRange(location: 0, length: 5))
        }

        @Test func `cancelling a composition records nothing`() {
            let (textView, bridge) = makeBridgedTextView()
            markText("に", replacing: NSRange(location: 0, length: 0), in: textView, forwardingTo: bridge)
            markText("にほ", replacing: NSRange(location: 0, length: 1), in: textView, forwardingTo: bridge)

            markText("", replacing: NSRange(location: 0, length: 2), in: textView, forwardingTo: bridge)

            #expect(textView.string == "")
            #expect(textView.hasMarkedText() == false)
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

        @Test func `undo of a deletion restores the deleted content and the preceding selection`() {
            let (textView, bridge) = makeBridgedTextView("abc")
            textView.setSelectedRange(NSRange(location: 3, length: 0))
            type("", replacing: NSRange(location: 2, length: 1), in: textView, forwardingTo: bridge)
            #expect(textView.string == "ab")

            bridge.undo()

            #expect(textView.string == "abc")
            #expect(textView.selectedRange == NSRange(location: 3, length: 0))
        }

        @Test func `redo of a deletion removes the content again and restores the post-deletion selection`() {
            let (textView, bridge) = makeBridgedTextView("abc")
            textView.setSelectedRange(NSRange(location: 3, length: 0))
            type("", replacing: NSRange(location: 2, length: 1), in: textView, forwardingTo: bridge)
            bridge.undo()

            bridge.redo()

            #expect(textView.string == "ab")
            #expect(textView.selectedRange == NSRange(location: 2, length: 0))
        }

        @Test func `undo of a selected-range deletion restores the deleted content as the selection`() {
            let (textView, bridge) = makeBridgedTextView("hello world")
            textView.setSelectedRange(NSRange(location: 5, length: 6))
            type("", replacing: NSRange(location: 5, length: 6), in: textView, forwardingTo: bridge)
            #expect(textView.string == "hello")

            bridge.undo()

            #expect(textView.string == "hello world")
            #expect(textView.selectedRange == NSRange(location: 5, length: 6))
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

    @MainActor
    @Suite struct ReentrancyGuard {
        @Test func `replay-driven view mutation records no forward entry`() {
            let (textView, bridge) = makeBridgedTextView()
            let delegate = ForwardingDelegate(bridge: bridge)
            textView.delegate = delegate
            defer { withExtendedLifetime(delegate) {} }

            textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))
            textView.insertText("b", replacementRange: NSRange(location: 1, length: 0))
            let historyAfterTyping = bridge.log.history
            #expect(historyAfterTyping.count == 2)

            bridge.undo()

            #expect(textView.string == "a")
            #expect(bridge.log.history == historyAfterTyping)
            #expect(bridge.log.canRedo)

            bridge.redo()

            #expect(textView.string == "ab")
            #expect(bridge.log.history == historyAfterTyping)
            #expect(bridge.log.canRedo == false)
        }

        @Test func `a consumer reading the log from a change callback during replay does not crash`() {
            let (textView, bridge) = makeBridgedTextView()
            let delegate = ForwardingDelegate(bridge: bridge)
            textView.delegate = delegate
            defer { withExtendedLifetime(delegate) {} }
            textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))

            var observedCanUndo: [Bool] = []
            delegate.onTextDidChange = { observedCanUndo.append(bridge.log.canUndo) }

            bridge.undo()

            #expect(textView.string == "")
            #expect(observedCanUndo == [true])
            #expect(bridge.log.canUndo == false)
            #expect(bridge.log.canRedo)
        }

        @Test func `replay re-emits the view's content-change callbacks for downstream consumers`() {
            let (textView, bridge) = makeBridgedTextView()
            let delegate = ForwardingDelegate(bridge: bridge)
            textView.delegate = delegate
            defer { withExtendedLifetime(delegate) {} }

            textView.insertText("a", replacementRange: NSRange(location: 0, length: 0))
            #expect(delegate.textDidChangeCount == 1)

            bridge.undo()

            #expect(delegate.textDidChangeCount == 2)
        }
    }
}
#endif
