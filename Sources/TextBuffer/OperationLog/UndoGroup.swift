import Foundation

public struct UndoGroup: Sendable, Equatable {
    public internal(set) var operations: [BufferOperation]
    public internal(set) var selectionBefore: NSRange
    public internal(set) var selectionAfter: NSRange?
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
