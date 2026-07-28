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

    public init(textView: NSTextView, log: OperationLog = OperationLog()) {
        self.textView = textView
        self.log = log
    }

    public func shouldChangeText(in affectedRange: NSRange, replacementString: String?) {
        guard let replacementString else { return }
        pendingChange = PendingChange(
            affectedRange: affectedRange,
            oldContent: textView.nsMutableString.substring(with: affectedRange),
            replacement: replacementString,
            selectionBefore: textView.selectedRange
        )
    }

    public func textDidChange() {
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
#endif
