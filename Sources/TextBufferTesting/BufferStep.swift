import Foundation

/// A single editing action that can be applied to a buffer in a test sequence.
///
/// Compose arrays of `BufferStep` values to drive ``assertUndoEquivalence(initial:steps:file:line:)``
/// and ``assertSendableUndoEquivalence(initial:steps:file:line:)``.
/// Use the ``group(actionName:steps:)`` case to nest multiple steps into a single undo group.
public enum BufferStep {
    case insert(content: String, at: Int)
    case delete(range: NSRange)
    case replace(range: NSRange, with: String)
    case select(NSRange)
    case undo
    case redo
    indirect case group(actionName: String?, steps: [BufferStep])
}
