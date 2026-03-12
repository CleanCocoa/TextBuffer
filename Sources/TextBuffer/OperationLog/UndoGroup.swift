import Foundation

public struct UndoGroup: Sendable, Equatable {
    public var operations: [BufferOperation]
    public var selectionBefore: NSRange
    public var selectionAfter: NSRange?
    public var actionName: String?

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
