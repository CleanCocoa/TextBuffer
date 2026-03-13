import Foundation

public struct OperationLog: Sendable, Equatable {
    public private(set) var history: [UndoGroup]
    public private(set) var cursor: Int
    @usableFromInline
    var groupingStack: [UndoGroup]

    @inlinable @inline(__always)
    public var isGrouping: Bool { !groupingStack.isEmpty }

    public init() {
        self.history = []
        self.cursor = 0
        self.groupingStack = []
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

    public mutating func undo<B: Buffer>(on buffer: B) -> NSRange? where B.Range == NSRange, B.Content == String {
        guard canUndo else { return nil }
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
