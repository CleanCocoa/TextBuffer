#if os(macOS)
import AppKit

/// Mirrors `NSTextView` edits into an ``OperationLog`` for transferable undo storage.
///
/// The text view remains the live content authority; the log records each edit as a
/// replayable delta. Forward the text view's delegate callbacks to
/// ``shouldChangeText(in:replacementString:)`` and ``textDidChange()`` to feed the mirror.
@MainActor
public final class NSTextViewOperationLogBridge {
    private struct PendingChange {
        var affectedRange: NSRange
        var oldContent: String
        var replacement: String
        var selectionBefore: NSRange
    }

    let textView: NSTextView
    public private(set) var log: OperationLog
    private var pendingChange: PendingChange?
    private var isReplaying = false
    private let replayBuffer: ReplayingNSTextViewBuffer
    private var puppetUndoManager: PuppetUndoManager?

    public init(textView: NSTextView, log: OperationLog = OperationLog()) {
        self.textView = textView
        self.log = log
        self.replayBuffer = ReplayingNSTextViewBuffer(textView: textView)
    }

    public func shouldChangeText(in affectedRange: NSRange, replacementString: String?) {
        guard !isReplaying else { return }
        guard let replacementString else { return }
        pendingChange = PendingChange(
            affectedRange: affectedRange,
            oldContent: textView.nsMutableString.substring(with: affectedRange),
            replacement: replacementString,
            selectionBefore: textView.selectedRange
        )
    }

    public func textDidChange() {
        guard !isReplaying else { return }
        guard let pending = pendingChange else { return }
        pendingChange = nil
        guard let operation = mirroredOperation(for: pending) else { return }
        log.beginUndoGroup(selectionBefore: pending.selectionBefore)
        log.record(operation)
        log.endUndoGroup(selectionAfter: textView.selectedRange)
    }

    private func mirroredOperation(for pending: PendingChange) -> BufferOperation? {
        switch (pending.affectedRange.length, pending.replacement.isEmpty) {
        case (0, true):
            return nil
        case (0, false):
            return BufferOperation(kind: .insert(content: pending.replacement, at: pending.affectedRange.location))
        case (_, true):
            return BufferOperation(kind: .delete(range: pending.affectedRange, deletedContent: pending.oldContent))
        case (_, false):
            return BufferOperation(kind: .replace(range: pending.affectedRange, oldContent: pending.oldContent, newContent: pending.replacement))
        }
    }
}

extension NSTextViewOperationLogBridge {
    public func undo() {
        isReplaying = true
        defer { isReplaying = false }
        _ = log.undo(on: replayBuffer)
    }

    public func redo() {
        isReplaying = true
        defer { isReplaying = false }
        _ = log.redo(on: replayBuffer)
    }
}

extension NSTextViewOperationLogBridge {
    public func enableSystemUndoIntegration() -> UndoManager {
        if let existing = puppetUndoManager { return existing }
        let puppet = PuppetUndoManager(owner: self)
        puppetUndoManager = puppet
        return puppet
    }
}

extension NSTextViewOperationLogBridge: PuppetUndoManagerDelegate {
    func puppetUndo() { undo() }
    func puppetRedo() { redo() }
    var puppetCanUndo: Bool { log.canUndo }
    var puppetCanRedo: Bool { log.canRedo }
    var puppetUndoActionName: String { log.undoActionName ?? "" }
    var puppetRedoActionName: String { log.redoActionName ?? "" }
}

/// Replays log operations through `NSTextView.insertText(_:replacementRange:)` so the view
/// re-emits its regular change callbacks for downstream consumers.
@MainActor
final class ReplayingNSTextViewBuffer: NSTextViewBuffer {
    override func insert(_ content: String, at location: Int) throws(BufferAccessFailure) {
        textView.insertText(content, replacementRange: NSRange(location: location, length: 0))
    }

    override func delete(in deletedRange: NSRange) throws(BufferAccessFailure) {
        textView.insertText("", replacementRange: deletedRange)
    }

    override func replace(range replacementRange: NSRange, with content: String) throws(BufferAccessFailure) {
        textView.insertText(content, replacementRange: replacementRange)
    }
}
#endif
