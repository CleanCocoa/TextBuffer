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

extension BufferOperation.Kind {
    /// Recorded text is compared in **UTF-8 code units**, not by Swift `String ==`
    /// (Unicode canonical equivalence), matching `TextRope`'s equality dialect — so a
    /// comparison spanning a buffer's content and its undo history, such as
    /// `SendableRopeBuffer.comparator(.content, .undoHistory)`, cannot answer one
    /// component in code units and the other canonically.
    ///
    /// **Field coverage is now manual.** Going explicit forfeits the synthesized
    /// conformance's automatic coverage of every associated value: a new case on `Kind`,
    /// or a new associated value on an existing case, that nobody adds here compiles
    /// fine and silently makes distinct operations compare equal — the worst failure
    /// direction for an undo log. Any such addition MUST extend this comparison in the
    /// same change. `testEveryPayloadOfEveryKindParticipatesInEquality` is the standing
    /// guard and must gain the new payload too.
    ///
    /// `BufferOperation`, ``UndoGroup``, and ``OperationLog`` keep their synthesized
    /// conformances and inherit this dialect through the chain.
    public static func == (lhs: BufferOperation.Kind, rhs: BufferOperation.Kind) -> Bool {
        switch (lhs, rhs) {
        case let (.insert(lhsContent, lhsAt), .insert(rhsContent, rhsAt)):
            return lhsAt == rhsAt
                && lhsContent.utf8.elementsEqual(rhsContent.utf8)
        case let (.delete(lhsRange, lhsDeletedContent), .delete(rhsRange, rhsDeletedContent)):
            return lhsRange == rhsRange
                && lhsDeletedContent.utf8.elementsEqual(rhsDeletedContent.utf8)
        case let (.replace(lhsRange, lhsOldContent, lhsNewContent), .replace(rhsRange, rhsOldContent, rhsNewContent)):
            return lhsRange == rhsRange
                && lhsOldContent.utf8.elementsEqual(rhsOldContent.utf8)
                && lhsNewContent.utf8.elementsEqual(rhsNewContent.utf8)
        case (.insert, _), (.delete, _), (.replace, _):
            return false
        }
    }
}
