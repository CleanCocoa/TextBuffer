import Foundation
import TextRope

public typealias InMemoryBuffer = SendableRopeBuffer
public typealias EditingBuffer = TransferableUndoable<RopeBuffer>

/// A `Sendable` value-type text buffer backed by a ``TextRope`` with built-in undo/redo via ``OperationLog``.
///
/// `SendableRopeBuffer` combines efficient rope-based text storage with a self-contained operation log,
/// making it safe to pass across actor boundaries while preserving full undo history.
///
/// ## Undo and Redo
///
/// Every mutation automatically records a ``BufferOperation`` in the ``log``. Individual mutations
/// are auto-wrapped in an ``UndoGroup``; use ``undoGrouping(actionName:_:)`` or the manual
/// ``beginUndoGroup(actionName:)`` / ``endUndoGroup()`` pair to group multiple mutations
/// into a single undoable step.
///
/// Call ``undo()`` and ``redo()`` to walk the history. Both return the restored selection, or `nil`
/// if there is nothing to undo/redo.
///
/// ## String Representation
///
/// The ``description`` uses `«guillemets»` for selections and `ˇ` for the insertion point,
/// matching the notation used by ``MutableStringBuffer`` and the `TextBufferTesting` helpers.
public struct SendableRopeBuffer: TextBuffer, TextAnalysisCapable, Sendable {
    public typealias Range = NSRange
    public typealias Content = String

    public internal(set) var rope: TextRope
    public var selectedRange: NSRange
    public internal(set) var log: OperationLog

    public init(_ content: String = "") {
        self.rope = TextRope(content)
        self.selectedRange = NSRange(location: 0, length: 0)
        self.log = OperationLog()
    }

    public init(_ content: String, selectedRange: NSRange) {
        self.rope = TextRope(content)
        self.selectedRange = selectedRange
        self.log = OperationLog()
    }

    @inlinable
    public var range: NSRange { NSRange(location: 0, length: rope.utf16Count) }

    @inlinable
    public var content: String { rope.content }

    public func content(in subrange: NSRange) throws(BufferAccessFailure) -> String {
        guard contains(range: subrange) else {
            throw BufferAccessFailure.outOfRange(
                requested: subrange,
                available: self.range
            )
        }
        return rope.content(in: subrange)
    }

    public func unsafeCharacter(at location: Int) -> String {
        return rope.content(in: NSRange(location: location, length: 1))
    }

    public mutating func insert(_ content: String, at location: Int) throws(BufferAccessFailure) {
        guard contains(range: NSRange(location: location, length: 0)) else {
            throw BufferAccessFailure.outOfRange(
                location: location,
                available: self.range
            )
        }

        let needsAutoGroup = !log.isGrouping
        if needsAutoGroup {
            log.beginUndoGroup(selectionBefore: selectedRange)
        }

        rope.insert(content, at: location)
        log.record(BufferOperation(kind: .insert(content: content, at: location)))

        self.selectedRange = self.selectedRange
            .shifted(by: location <= self.selectedRange.location ? content.utf16.count : 0)

        if needsAutoGroup {
            log.endUndoGroup(selectionAfter: selectedRange)
        }
    }

    public mutating func delete(in deletedRange: NSRange) throws(BufferAccessFailure) {
        guard contains(range: deletedRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: deletedRange,
                available: self.range
            )
        }

        let needsAutoGroup = !log.isGrouping
        if needsAutoGroup {
            log.beginUndoGroup(selectionBefore: selectedRange)
        }

        let oldContent = rope.content(in: deletedRange)
        rope.delete(in: deletedRange)
        log.record(BufferOperation(kind: .delete(range: deletedRange, deletedContent: oldContent)))

        self.selectedRange.subtract(deletedRange)

        if needsAutoGroup {
            log.endUndoGroup(selectionAfter: selectedRange)
        }
    }

    public mutating func replace(range replacementRange: NSRange, with content: String) throws(BufferAccessFailure) {
        guard contains(range: replacementRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: replacementRange,
                available: self.range
            )
        }

        let needsAutoGroup = !log.isGrouping
        if needsAutoGroup {
            log.beginUndoGroup(selectionBefore: selectedRange)
        }

        let oldContent = rope.content(in: replacementRange)
        rope.replace(range: replacementRange, with: content)
        log.record(BufferOperation(kind: .replace(range: replacementRange, oldContent: oldContent, newContent: content)))

        self.selectedRange = self.selectedRange
            .subtracting(replacementRange)
            .shifted(by: replacementRange.location <= self.selectedRange.location ? content.utf16.count : 0)

        if needsAutoGroup {
            log.endUndoGroup(selectionAfter: selectedRange)
        }
    }

    public mutating func modifying<T>(affectedRange: NSRange, _ block: () -> T) throws(BufferAccessFailure) -> T {
        guard contains(range: affectedRange) else {
            throw BufferAccessFailure.outOfRange(
                requested: affectedRange,
                available: self.range
            )
        }
        return block()
    }
}

extension SendableRopeBuffer {
    public mutating func undoGrouping<T>(actionName: String? = nil, _ block: (inout Self) throws -> T) rethrows -> T {
        log.beginUndoGroup(selectionBefore: selectedRange, actionName: actionName)
        let result = try block(&self)
        log.endUndoGroup(selectionAfter: selectedRange)
        return result
    }

    public mutating func beginUndoGroup(actionName: String? = nil) {
        log.beginUndoGroup(selectionBefore: selectedRange, actionName: actionName)
    }

    public mutating func endUndoGroup() {
        log.endUndoGroup(selectionAfter: selectedRange)
    }
}

extension SendableRopeBuffer {
    public var canUndo: Bool { log.canUndo }
    public var canRedo: Bool { log.canRedo }

    @discardableResult
    public mutating func undo() -> NSRange? {
        guard let group = log.popUndo() else { return nil }
        for operation in group.operations.reversed() {
            switch operation.kind {
            case .insert(let content, let at):
                rope.delete(in: NSRange(location: at, length: content.utf16.count))
            case .delete(let range, let deletedContent):
                rope.insert(deletedContent, at: range.location)
            case .replace(let range, let oldContent, let newContent):
                rope.replace(range: NSRange(location: range.location, length: newContent.utf16.count), with: oldContent)
            }
        }
        selectedRange = group.selectionBefore
        return group.selectionBefore
    }

    @discardableResult
    public mutating func redo() -> NSRange? {
        guard let group = log.popRedo() else { return nil }
        for operation in group.operations {
            switch operation.kind {
            case .insert(let content, let at):
                rope.insert(content, at: at)
            case .delete(let range, _):
                rope.delete(in: range)
            case .replace(let range, _, let newContent):
                rope.replace(range: range, with: newContent)
            }
        }
        guard let selectionAfter = group.selectionAfter else {
            preconditionFailure("SendableRopeBuffer invariant violated: redo group missing selectionAfter")
        }
        selectedRange = selectionAfter
        return selectionAfter
    }
}

extension SendableRopeBuffer {
    public enum ComparisonComponent: Sendable {
        case content
        case selection
        case undoHistory
    }

    public static func comparator(
        _ first: ComparisonComponent,
        _ rest: ComparisonComponent...
    ) -> @Sendable (SendableRopeBuffer, SendableRopeBuffer) -> Bool {
        let components = [first] + rest
        return { lhs, rhs in
            for component in components {
                switch component {
                case .content:
                    guard lhs.rope == rhs.rope else { return false }
                case .selection:
                    guard lhs.selectedRange == rhs.selectedRange else { return false }
                case .undoHistory:
                    guard lhs.log == rhs.log else { return false }
                }
            }
            return true
        }
    }
}

extension SendableRopeBuffer: CustomStringConvertible {
    public var description: String {
        let result = NSMutableString(string: content)
        if isSelectingText {
            result.insert("»", at: selectedRange.endLocation)
            result.insert("«", at: selectedRange.location)
        } else {
            result.insert("ˇ", at: selectedRange.location)
        }
        return result as String
    }
}
