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
        var textLengthBefore: Int

        func isConsistent(with string: NSMutableString) -> Bool {
            let expectedLength = textLengthBefore - affectedRange.length + replacement.utf16.count
            guard string.length == expectedLength else { return false }
            let replacedRange = NSRange(location: affectedRange.location, length: replacement.utf16.count)
            return string.substring(with: replacedRange) == replacement
        }

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

    private let textView: NSTextView

    /// The mirrored undo history. A value type: copy it to snapshot or transfer undo state.
    public private(set) var log: OperationLog
    private var pendingChange: PendingChange?
    private var compositionBaseline: PendingChange?
    private var isReplaying = false
    private let replayBuffer: ReplayingNSTextViewBuffer
    private var puppetUndoManager: PuppetUndoManager?

    public init(textView: NSTextView, log: OperationLog = OperationLog()) {
        self.textView = textView
        var log = log
        log.breakCoalescing()
        self.log = log
        self.replayBuffer = ReplayingNSTextViewBuffer(textView: textView)
    }

    /// Stages the edit the text view is about to perform. Forward from
    /// `NSTextViewDelegate.textView(_:shouldChangeTextIn:replacementString:)`.
    ///
    /// A `nil` `replacementString` (attribute-only change) stages nothing and invalidates any
    /// previously staged edit that never committed — e.g. one whose delegate callback the host
    /// vetoed after forwarding it here. The bridge never vetoes an edit; the delegate's return
    /// value remains the caller's decision.
    ///
    /// While the view `hasMarkedText()`, composition intermediates stage nothing; the finished
    /// composition is recorded once, from the baseline staged when composition began. If
    /// composition ended without a character-changing `textDidChange` (an unmark), the stale
    /// baseline is resolved first — committed or discarded against the view's current content —
    /// so the new edit cannot be folded into stale composition math.
    public func shouldChangeText(in affectedRange: NSRange, replacementString: String?) {
        guard !isReplaying else { return }
        guard !textView.hasMarkedText() else {
            pendingChange = nil
            return
        }
        if let baseline = compositionBaseline {
            compositionBaseline = nil
            commitComposition(from: baseline)
        }
        guard let replacementString else {
            pendingChange = nil
            return
        }
        pendingChange = PendingChange(
            affectedRange: affectedRange,
            oldContent: textView.nsMutableString.substring(with: affectedRange),
            replacement: replacementString,
            selectionBefore: textView.selectedRange,
            textLengthBefore: textView.nsMutableString.length
        )
    }

    /// Commits the staged edit to the log as one undo group. Forward from
    /// `NSTextDelegate.textDidChange(_:)`. Without a staged edit, this is a no-op.
    ///
    /// When the view's content is inconsistent with the staged edit — e.g. a multi-range edit
    /// like find-and-replace-all funneled more than one range through
    /// ``shouldChangeText(in:replacementString:)`` — the bridge discards the log instead of
    /// recording an operation that would not replay: stale history replayed against diverged
    /// content would corrupt it.
    public func textDidChange() {
        guard !isReplaying else { return }
        if textView.hasMarkedText() {
            if compositionBaseline == nil {
                compositionBaseline = pendingChange
            }
            pendingChange = nil
            return
        }
        if let baseline = compositionBaseline {
            compositionBaseline = nil
            pendingChange = nil
            commitComposition(from: baseline)
            return
        }
        guard let pending = pendingChange else { return }
        pendingChange = nil
        commit(pending)
    }

    private func commit(_ pending: PendingChange) {
        guard pending.isConsistent(with: textView.nsMutableString) else {
            log = OperationLog()
            return
        }
        guard let operation = pending.bufferOperation else { return }
        log.coalesce(operation, selectionBefore: pending.selectionBefore, selectionAfter: textView.selectedRange)
    }

    /// Records a finished marked-text composition as one edit: the pre-composition range the
    /// baseline staged, replaced by whatever the view holds there now. The committed length is
    /// the view's length delta since the baseline plus the baseline range's length; a cancelled
    /// composition restores the baseline content and records nothing. A commit is its own undo
    /// group, macOS per-clause style: it neither joins a preceding typing run nor opens one.
    private func commitComposition(from baseline: PendingChange) {
        let length = textView.nsMutableString.length
        let committedLength = length - baseline.textLengthBefore + baseline.affectedRange.length
        guard committedLength >= 0, baseline.affectedRange.location + committedLength <= length else {
            log = OperationLog()
            return
        }
        var committed = baseline
        committed.replacement = textView.nsMutableString.substring(
            with: NSRange(location: baseline.affectedRange.location, length: committedLength)
        )
        guard committed.replacement != baseline.oldContent else { return }
        log.breakCoalescing()
        commit(committed)
        log.breakCoalescing()
    }
}

extension NSTextViewOperationLogBridge {
    /// Ends the current typing run so the next edit starts a new undo group.
    ///
    /// Continuous typing coalesces into one undo group, macOS-style — never one group per
    /// keystroke. The bridge cannot observe interaction breaks itself, so forward them from the
    /// host app: mouse-down in the view, cursor repositioning, focus changes.
    public func breakUndoCoalescing() {
        log.breakCoalescing()
    }
}

extension NSTextViewOperationLogBridge {
    /// Captures the view's content, selection, and the mirrored ``log`` as a ``SendableRopeBuffer``
    /// for storage or transfer across actor boundaries, mirroring
    /// ``TransferableUndoable/sendableSnapshot()``.
    ///
    /// To restore, configure a fresh view from the snapshot's content and selection, then hand the
    /// snapshot's log to ``init(textView:log:)``.
    public func sendableSnapshot() -> SendableRopeBuffer {
        var snapshot = SendableRopeBuffer(textView.string)
        snapshot.selectedRange = textView.selectedRange
        snapshot.log = log
        return snapshot
    }
}

extension NSTextViewOperationLogBridge {
    /// Replays the most recent undo group back onto the text view, restoring content and selection.
    ///
    /// Replay makes the view emit its regular change callbacks for downstream consumers; the
    /// bridge suppresses re-recording. Callbacks observe ``log`` as it was before the replay;
    /// the replayed log is written back afterwards.
    public func undo() {
        isReplaying = true
        defer { isReplaying = false }
        // Replay on a copy: mutating `log` directly would hold exclusive access on it while the view re-emits change callbacks, trapping any consumer that reads `log` from those callbacks.
        var replayed = log
        _ = replayed.undo(on: replayBuffer)
        log = replayed
    }

    /// Reapplies the most recently undone group onto the text view, restoring content and selection.
    public func redo() {
        isReplaying = true
        defer { isReplaying = false }
        var replayed = log
        _ = replayed.redo(on: replayBuffer)
        log = replayed
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

/// Replays log operations onto the view wrapped in `shouldChangeText(in:replacementString:)`
/// and `didChangeText()` so the view re-emits its regular change callbacks for downstream
/// consumers, and a vetoed or non-editable replay surfaces as ``BufferAccessFailure`` instead
/// of silently no-oping while the log cursor advances.
@MainActor
final class ReplayingNSTextViewBuffer: NSTextViewBuffer {
    override func insert(_ content: String, at location: Int) throws(BufferAccessFailure) {
        let affectedRange = NSRange(location: location, length: 0)
        guard textView.shouldChangeText(in: affectedRange, replacementString: content) else {
            throw BufferAccessFailure.modificationForbidden(in: affectedRange)
        }
        try super.insert(content, at: location)
        textView.didChangeText()
    }

    override func delete(in deletedRange: NSRange) throws(BufferAccessFailure) {
        guard textView.shouldChangeText(in: deletedRange, replacementString: "") else {
            throw BufferAccessFailure.modificationForbidden(in: deletedRange)
        }
        try super.delete(in: deletedRange)
        textView.didChangeText()
    }

    override func replace(range replacementRange: NSRange, with content: String) throws(BufferAccessFailure) {
        guard textView.shouldChangeText(in: replacementRange, replacementString: content) else {
            throw BufferAccessFailure.modificationForbidden(in: replacementRange)
        }
        try super.replace(range: replacementRange, with: content)
        textView.didChangeText()
    }
}
#endif
