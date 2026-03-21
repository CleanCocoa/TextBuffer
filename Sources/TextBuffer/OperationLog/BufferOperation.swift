import Foundation

/// A single buffer mutation recorded for replay-based undo and redo.
///
/// Each operation captures enough information to reverse itself:
/// insertions record the inserted text and location, deletions record the deleted range and its former content,
/// and replacements record both the old and new content.
///
/// Operations are collected into ``UndoGroup``s by an ``OperationLog``.
public struct BufferOperation: Sendable, Equatable {
    /// The kind of mutation that was performed.
    public enum Kind: Sendable, Equatable {
        /// Text was inserted at a UTF-16 offset.
        case insert(content: String, at: Int)
        /// Text in the given range was deleted; `deletedContent` preserves the removed text for undo.
        case delete(range: NSRange, deletedContent: String)
        /// Text in the given range was replaced; both old and new content are preserved.
        case replace(range: NSRange, oldContent: String, newContent: String)
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }
}
