import Foundation

/// A linear undo history that records ``BufferOperation``s grouped into ``UndoGroup``s.
///
/// `OperationLog` maintains a flat history array with a cursor separating undoable from redoable groups.
/// New groups are appended at the cursor, discarding any redo history beyond it.
///
/// ## Grouping
///
/// Every recorded operation must be inside an undo group. Call ``beginUndoGroup(selectionBefore:actionName:)``
/// before mutations and ``endUndoGroup(selectionAfter:)`` after. Groups can be nested; inner groups merge
/// their operations into the outermost group.
///
/// ## Replaying
///
/// Use ``undo(on:)`` and ``redo(on:)`` to replay operations on any ``Buffer``, or use ``popUndo()``
/// and ``popRedo()`` to retrieve groups for manual replay (as ``SendableRopeBuffer`` does).
public struct OperationLog: Sendable, Equatable {
    public private(set) var history: [UndoGroup]
    public private(set) var cursor: Int
    @usableFromInline
    var groupingStack: [UndoGroup]
    var isCoalescing: Bool

    @inlinable @inline(__always)
    public var isGrouping: Bool { !groupingStack.isEmpty }

    public init() {
        self.history = []
        self.cursor = 0
        self.groupingStack = []
        self.isCoalescing = false
    }

    public mutating func beginUndoGroup(selectionBefore: NSRange, actionName: String? = nil) {
        groupingStack.append(UndoGroup(selectionBefore: selectionBefore, actionName: actionName))
    }

    public mutating func endUndoGroup(selectionAfter: NSRange) {
        precondition(!groupingStack.isEmpty, "endUndoGroup called without a matching beginUndoGroup")
        var group = groupingStack.removeLast()
        group.selectionAfter = selectionAfter

        if groupingStack.isEmpty {
            history.removeSubrange(cursor...)
            history.append(group)
            cursor = history.count
            isCoalescing = false
        } else {
            groupingStack[groupingStack.count - 1].operations.append(contentsOf: group.operations)
            if groupingStack[groupingStack.count - 1].actionName == nil, let name = group.actionName {
                groupingStack[groupingStack.count - 1].actionName = name
            }
        }
    }

    public mutating func record(_ operation: BufferOperation) {
        precondition(!groupingStack.isEmpty, "record(_:) called outside of an undo group")
        groupingStack[groupingStack.count - 1].operations.append(operation)
    }

    @inlinable @inline(__always)
    public var canUndo: Bool { cursor > 0 }

    @inlinable @inline(__always)
    public var canRedo: Bool { cursor < history.count }

    @inlinable @inline(__always)
    public var undoableCount: Int { cursor }

    @inlinable @inline(__always)
    public var undoActionName: String? { canUndo ? history[cursor - 1].actionName : nil }

    @inlinable @inline(__always)
    public var redoActionName: String? { canRedo ? history[cursor].actionName : nil }

    public func actionName(at index: Int) -> String? {
        guard index >= 0, index < history.count else { return nil }
        return history[index].actionName
    }

    public mutating func popUndo() -> UndoGroup? {
        guard canUndo else { return nil }
        isCoalescing = false
        cursor -= 1
        return history[cursor]
    }

    public mutating func popRedo() -> UndoGroup? {
        guard canRedo else { return nil }
        isCoalescing = false
        let group = history[cursor]
        cursor += 1
        return group
    }

    public mutating func undo<B: Buffer>(on buffer: B) -> NSRange? where B.Range == NSRange, B.Content == String {
        guard canUndo else { return nil }
        isCoalescing = false
        cursor -= 1
        let group = history[cursor]
        for operation in group.operations.reversed() {
            do {
                switch operation.kind {
                case .insert(let content, let at):
                    try buffer.delete(in: NSRange(location: at, length: content.utf16.count))
                case .delete(let range, let deletedContent):
                    try buffer.insert(deletedContent, at: range.location)
                case .replace(let range, let oldContent, let newContent):
                    try buffer.replace(range: NSRange(location: range.location, length: newContent.utf16.count), with: oldContent)
                }
            } catch {
                preconditionFailure("OperationLog invariant violated: undo replay failed for \(operation.kind) — \(error)")
            }
        }
        buffer.selectedRange = group.selectionBefore
        return group.selectionBefore
    }

    public mutating func redo<B: Buffer>(on buffer: B) -> NSRange? where B.Range == NSRange, B.Content == String {
        guard canRedo else { return nil }
        isCoalescing = false
        let group = history[cursor]
        cursor += 1
        for operation in group.operations {
            do {
                switch operation.kind {
                case .insert(let content, let at):
                    try buffer.insert(content, at: at)
                case .delete(let range, _):
                    try buffer.delete(in: range)
                case .replace(let range, _, let newContent):
                    try buffer.replace(range: range, with: newContent)
                }
            } catch {
                preconditionFailure("OperationLog invariant violated: redo replay failed for \(operation.kind) — \(error)")
            }
        }
        guard let selectionAfter = group.selectionAfter else {
            preconditionFailure("OperationLog invariant violated: redo group missing selectionAfter")
        }
        buffer.selectedRange = selectionAfter
        return group.selectionAfter
    }
}

extension OperationLog {
    /// Compares recorded history only. Whether a typing run is open is transient interaction
    /// state, so a coalescing break (e.g. a mouse click) never reads as a history change.
    public static func == (lhs: OperationLog, rhs: OperationLog) -> Bool {
        lhs.history == rhs.history
            && lhs.cursor == rhs.cursor
            && lhs.groupingStack == rhs.groupingStack
    }
}

extension OperationLog {
    /// Records `operation` as part of the current typing run, or starts a new group.
    ///
    /// The run extends only while coalescing is active, the cursor sits at the end of history,
    /// and the operation continues the run's last operation in kind and position: a
    /// single-character insert continues exactly where the run's last insert ended; a delete
    /// continues a backspace run (its end meets the previous delete's start) or a forward-delete
    /// run (same location as the previous delete). The extended group keeps its original
    /// `selectionBefore` and adopts `selectionAfter`. Anything else — a break via
    /// ``breakCoalescing()``, undo/redo, an explicit group, a replace, a multi-character insert
    /// (paste), or a kind or position mismatch — records a fresh group; a single-character insert
    /// or a delete opens a new run, a multi-character insert or a replace never does.
    ///
    /// A group that opens a run is named "Typing" (unlocalized — the package ships no
    /// localization tables), so `undoMenuItemTitle` on a system undo manager yields
    /// "Undo Typing", matching native `NSTextView` undo. Multi-character inserts and replaces
    /// stay unnamed: the log cannot tell a paste from a drop, and a wrong name is worse than a
    /// bare "Undo".
    mutating func coalesce(_ operation: BufferOperation, selectionBefore: NSRange, selectionAfter: NSRange) {
        if isCoalescing,
           cursor == history.count,
           let runKind = history.last?.operations.last?.kind,
           operation.kind.extendsRun(endingIn: runKind) {
            history[cursor - 1].operations.append(operation)
            history[cursor - 1].selectionAfter = selectionAfter
        } else {
            let opensRun: Bool
            switch operation.kind {
            case .insert(let content, _):
                opensRun = content.count == 1
            case .delete:
                opensRun = true
            case .replace:
                opensRun = false
            }
            beginUndoGroup(selectionBefore: selectionBefore, actionName: opensRun ? "Typing" : nil)
            record(operation)
            endUndoGroup(selectionAfter: selectionAfter)
            switch operation.kind {
            case .insert(let content, _):
                isCoalescing = content.count == 1
            case .delete:
                isCoalescing = true
            case .replace:
                break
            }
        }
    }

    mutating func breakCoalescing() {
        isCoalescing = false
    }
}

extension BufferOperation.Kind {
    func extendsRun(endingIn runKind: BufferOperation.Kind) -> Bool {
        switch (runKind, self) {
        case (.insert(let runContent, let runLocation), .insert(let content, let location)):
            return content.count == 1 && runLocation + runContent.utf16.count == location
        case (.delete(let previousRange, _), .delete(let nextRange, _)):
            return nextRange.location + nextRange.length == previousRange.location
                || nextRange.location == previousRange.location
        default:
            return false
        }
    }
}
