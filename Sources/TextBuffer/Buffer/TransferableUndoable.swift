import Foundation

@MainActor
public final class TransferableUndoable<Base>: @MainActor Buffer where Base: Buffer, Base.Range == NSRange, Base.Content == String {
    public typealias Range = NSRange
    public typealias Content = String

    private let base: Base
    public var log: OperationLog
    private var puppetUndoManager: PuppetUndoManager?

    public init(_ base: Base) {
        self.base = base
        self.log = OperationLog()
    }

    init(_ base: Base, log: OperationLog) {
        self.base = base
        self.log = log
    }

    public var content: String { base.content }
    public var range: NSRange { base.range }
    public var selectedRange: NSRange {
        get { base.selectedRange }
        set { base.selectedRange = newValue }
    }

    public func content(in subrange: NSRange) throws(BufferAccessFailure) -> String {
        try base.content(in: subrange)
    }

    public func unsafeCharacter(at location: Int) -> String {
        base.unsafeCharacter(at: location)
    }

    public func insert(_ content: String, at location: Int) throws(BufferAccessFailure) {
        let needsAutoGroup = !log.isGrouping
        if needsAutoGroup {
            log.beginUndoGroup(selectionBefore: base.selectedRange)
        }
        try base.insert(content, at: location)
        log.record(BufferOperation(kind: .insert(content: content, at: location)))
        if needsAutoGroup {
            log.endUndoGroup(selectionAfter: base.selectedRange)
        }
    }

    public func delete(in deletedRange: NSRange) throws(BufferAccessFailure) {
        let needsAutoGroup = !log.isGrouping
        if needsAutoGroup {
            log.beginUndoGroup(selectionBefore: base.selectedRange)
        }
        let oldContent = try base.content(in: deletedRange)
        try base.delete(in: deletedRange)
        log.record(BufferOperation(kind: .delete(range: deletedRange, deletedContent: oldContent)))
        if needsAutoGroup {
            log.endUndoGroup(selectionAfter: base.selectedRange)
        }
    }

    public func replace(range replacementRange: NSRange, with content: String) throws(BufferAccessFailure) {
        let needsAutoGroup = !log.isGrouping
        if needsAutoGroup {
            log.beginUndoGroup(selectionBefore: base.selectedRange)
        }
        let oldContent = try base.content(in: replacementRange)
        try base.replace(range: replacementRange, with: content)
        log.record(BufferOperation(kind: .replace(range: replacementRange, oldContent: oldContent, newContent: content)))
        if needsAutoGroup {
            log.endUndoGroup(selectionAfter: base.selectedRange)
        }
    }

    public func modifying<T>(affectedRange: NSRange, _ block: () -> T) throws(BufferAccessFailure) -> T {
        let needsAutoGroup = !log.isGrouping
        if needsAutoGroup {
            log.beginUndoGroup(selectionBefore: base.selectedRange)
        }
        let oldContent = try base.content(in: affectedRange)
        let oldLength = base.range.length
        let result = try base.modifying(affectedRange: affectedRange, block)
        let newLength = base.range.length
        let lengthDelta = newLength - oldLength
        let newAffectedLength = affectedRange.length + lengthDelta
        let newContent = try! base.content(in: NSRange(location: affectedRange.location, length: newAffectedLength))
        log.record(BufferOperation(kind: .replace(range: affectedRange, oldContent: oldContent, newContent: newContent)))
        if needsAutoGroup {
            log.endUndoGroup(selectionAfter: base.selectedRange)
        }
        return result
    }
}

extension TransferableUndoable {
    public func undoGrouping<T>(actionName: String? = nil, _ block: () throws -> T) rethrows -> T {
        log.beginUndoGroup(selectionBefore: base.selectedRange, actionName: actionName)
        let result = try block()
        log.endUndoGroup(selectionAfter: base.selectedRange)
        return result
    }
}

extension TransferableUndoable {
    public var canUndo: Bool { log.canUndo }
    public var canRedo: Bool { log.canRedo }

    public func undo() {
        _ = log.undo(on: base)
    }

    public func redo() {
        _ = log.redo(on: base)
    }
}

extension TransferableUndoable {
    public func enableSystemUndoIntegration() -> UndoManager {
        if let existing = puppetUndoManager { return existing }
        let puppet = PuppetUndoManager(owner: self)
        puppetUndoManager = puppet
        return puppet
    }
}

extension TransferableUndoable: PuppetUndoManagerDelegate {
    func puppetUndo() { undo() }
    func puppetRedo() { redo() }
    var puppetCanUndo: Bool { log.canUndo }
    var puppetCanRedo: Bool { log.canRedo }
    var puppetUndoActionName: String { log.undoActionName ?? "" }
    var puppetRedoActionName: String { log.redoActionName ?? "" }
}

extension TransferableUndoable: @MainActor TextAnalysisCapable where Base: TextAnalysisCapable {
    public func lineRange(for searchRange: NSRange) throws(BufferAccessFailure) -> NSRange {
        try base.lineRange(for: searchRange)
    }
}

extension TransferableUndoable {
    public func snapshot() -> TransferableUndoable<MutableStringBuffer> {
        return TransferableUndoable<MutableStringBuffer>(
            MutableStringBuffer(wrapping: base),
            log: log
        )
    }
}

extension TransferableUndoable {
    public func represent<Source: Buffer>(_ source: TransferableUndoable<Source>) where Source.Range == NSRange, Source.Content == String {
        precondition(!log.isGrouping, "represent(_:) called while an undo group is open")
        try! base.replace(range: base.range, with: source.content)
        base.selectedRange = source.selectedRange
        log = source.log
    }
}
