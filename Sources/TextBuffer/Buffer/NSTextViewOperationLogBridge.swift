#if os(macOS)
import AppKit

/// Mirrors `NSTextView` edits into an ``OperationLog`` for transferable undo storage.
///
/// The text view remains the live content authority; the log records each edit as a
/// replayable delta. Feed the mirror by forwarding the text view's delegate callbacks:
///
/// ```swift
/// func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
///     bridge.shouldChangeText(in: affectedCharRange, replacementString: replacementString)
///     return true
/// }
///
/// func textDidChange(_ notification: Notification) {
///     bridge.textDidChange()
/// }
/// ```
///
/// ``undo()`` and ``redo()`` replay log groups back onto the view, restoring content and
/// selection. Call ``enableSystemUndoIntegration()`` to route AppKit's Edit menu and Cmd+Z
/// to the log.
@MainActor
public final class NSTextViewOperationLogBridge {
    private struct PendingChange {
        var affectedRange: NSRange
        var oldContent: String
        var replacement: String
        var selectionBefore: NSRange

        var bufferOperation: BufferOperation? {
            switch (affectedRange.length, replacement.isEmpty) {
            case (0, true):
                return nil
            case (0, false):
                return BufferOperation(kind: .insert(content: replacement, at: affectedRange.location))
            case (_, true):
                return BufferOperation(kind: .delete(range: affectedRange, deletedContent: oldContent))
            case (_, false):
                return BufferOperation(kind: .replace(range: affectedRange, oldContent: oldContent, newContent: replacement))
            }
        }
    }

    let textView: NSTextView

    /// The mirrored undo history. A value type: copy it to snapshot or transfer undo state.
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

    /// Stages the edit the text view is about to perform. Forward from
    /// `NSTextViewDelegate.textView(_:shouldChangeTextIn:replacementString:)`.
    ///
    /// A `nil` `replacementString` (attribute-only change) stages nothing. The bridge never
    /// vetoes an edit; the delegate's return value remains the caller's decision.
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

    /// Commits the staged edit to the log as one undo group. Forward from
    /// `NSTextDelegate.textDidChange(_:)`. Without a staged edit, this is a no-op.
    public func textDidChange() {
        guard !isReplaying else { return }
        guard let pending = pendingChange else { return }
        pendingChange = nil
        guard let operation = pending.bufferOperation else { return }
        log.beginUndoGroup(selectionBefore: pending.selectionBefore)
        log.record(operation)
        log.endUndoGroup(selectionAfter: textView.selectedRange)
    }
}

extension NSTextViewOperationLogBridge {
    /// Replays the most recent undo group back onto the text view, restoring content and selection.
    ///
    /// Replay goes through `NSTextView.insertText(_:replacementRange:)`, so the view emits its
    /// regular change callbacks for downstream consumers; the bridge suppresses re-recording.
    public func undo() {
        isReplaying = true
        defer { isReplaying = false }
        _ = log.undo(on: replayBuffer)
    }

    /// Reapplies the most recently undone group onto the text view, restoring content and selection.
    public func redo() {
        isReplaying = true
        defer { isReplaying = false }
        _ = log.redo(on: replayBuffer)
    }
}

extension NSTextViewOperationLogBridge {
    /// Returns an `UndoManager` that routes undo/redo to this bridge's ``OperationLog``.
    ///
    /// Assign it to your window or document (e.g. via
    /// `NSWindowDelegate.windowWillReturnUndoManager(_:)`) to enable AppKit's Edit menu items
    /// and Cmd+Z. Repeated calls return the same instance.
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
