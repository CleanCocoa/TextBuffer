import Foundation

/// An atomic undo step containing one or more ``BufferOperation``s and the selection state before and after.
///
/// When undone, all operations in the group are reversed in order, and the selection is restored
/// to ``selectionBefore``. When redone, operations are replayed and the selection moves to ``selectionAfter``.
public struct UndoGroup: Sendable, Equatable {
    public internal(set) var operations: [BufferOperation]
    public internal(set) var selectionBefore: NSRange
    public internal(set) var selectionAfter: NSRange?
    /// Deliberately outside the code-unit equality dialect that ``BufferOperation/Kind``
    /// enforces: this is a user-facing menu label, not recorded document text, so the
    /// synthesized `Equatable` compares it with Swift `String ==` — a canonically
    /// equivalent action name names the same command.
    public internal(set) var actionName: String?

    public init(
        operations: [BufferOperation] = [],
        selectionBefore: NSRange,
        selectionAfter: NSRange? = nil,
        actionName: String? = nil
    ) {
        self.operations = operations
        self.selectionBefore = selectionBefore
        self.selectionAfter = selectionAfter
        self.actionName = actionName
    }
}
