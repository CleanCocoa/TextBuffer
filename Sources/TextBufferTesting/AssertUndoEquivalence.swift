import Foundation
import XCTest
import TextBuffer

@MainActor
private func applyStep(_ step: BufferStep, to buffer: Undoable<MutableStringBuffer>) {
    switch step {
    case .insert(let content, let at):
        try! buffer.insert(content, at: at)
    case .delete(let range):
        try! buffer.delete(in: range)
    case .replace(let range, let with):
        try! buffer.replace(range: range, with: with)
    case .select(let range):
        buffer.select(range)
    case .undo:
        buffer.undo()
    case .redo:
        buffer.redo()
    case .group(let actionName, let steps):
        buffer.undoGrouping(actionName: actionName) {
            for s in steps { applyStep(s, to: buffer) }
        }
    }
}

@MainActor
private func applyStep(_ step: BufferStep, to buffer: TransferableUndoable<MutableStringBuffer>) {
    switch step {
    case .insert(let content, let at):
        try! buffer.insert(content, at: at)
    case .delete(let range):
        try! buffer.delete(in: range)
    case .replace(let range, let with):
        try! buffer.replace(range: range, with: with)
    case .select(let range):
        buffer.select(range)
    case .undo:
        buffer.undo()
    case .redo:
        buffer.redo()
    case .group(let actionName, let steps):
        buffer.undoGrouping(actionName: actionName) {
            for s in steps { applyStep(s, to: buffer) }
        }
    }
}

/// Verifies that an `Undoable` reference and a `TransferableUndoable` subject
/// produce identical content and selection after each step.
@MainActor
public func assertUndoEquivalence(
    reference: Undoable<MutableStringBuffer>,
    subject: TransferableUndoable<MutableStringBuffer>,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for (index, step) in steps.enumerated() {
        applyStep(step, to: reference)
        applyStep(step, to: subject)
        XCTAssertEqual(reference.content, subject.content, "Content diverged at step \(index): \(step)", file: file, line: line)
        XCTAssertEqual(reference.selectedRange, subject.selectedRange, "Selection diverged at step \(index): \(step)", file: file, line: line)
    }
}

/// Convenience that creates both an `Undoable` and a `TransferableUndoable`
/// from `initial` and compares them through `steps`.
@MainActor
public func assertUndoEquivalence(
    initial: String,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let reference = Undoable(MutableStringBuffer(initial))
    let subject = TransferableUndoable(MutableStringBuffer(initial))
    assertUndoEquivalence(reference: reference, subject: subject, steps: steps, file: file, line: line)
}

/// Applies a single ``BufferStep`` to a `SendableRopeBuffer`.
public func applyStep(_ step: BufferStep, to buffer: inout SendableRopeBuffer) {
    switch step {
    case .insert(let content, let at):
        try! buffer.insert(content, at: at)
    case .delete(let range):
        try! buffer.delete(in: range)
    case .replace(let range, let with):
        try! buffer.replace(range: range, with: with)
    case .select(let range):
        buffer.select(range)
    case .undo:
        _ = buffer.undo()
    case .redo:
        _ = buffer.redo()
    case .group(let actionName, let steps):
        buffer.undoGrouping(actionName: actionName) { buf in
            for s in steps { applyStep(s, to: &buf) }
        }
    }
}

/// Verifies that a `TransferableUndoable` reference and a `SendableRopeBuffer` subject
/// produce identical content and selection after each step.
@MainActor
public func assertUndoEquivalence(
    reference: TransferableUndoable<MutableStringBuffer>,
    subject: inout SendableRopeBuffer,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for (index, step) in steps.enumerated() {
        applyStep(step, to: reference)
        applyStep(step, to: &subject)
        XCTAssertEqual(reference.content, subject.content, "Content diverged at step \(index): \(step)", file: file, line: line)
        XCTAssertEqual(reference.selectedRange, subject.selectedRange, "Selection diverged at step \(index): \(step)", file: file, line: line)
    }
}

/// Convenience that creates a `TransferableUndoable` and a `SendableRopeBuffer`
/// from `initial` and compares them through `steps`.
@MainActor
public func assertSendableUndoEquivalence(
    initial: String,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let reference = TransferableUndoable(MutableStringBuffer(initial))
    var subject = SendableRopeBuffer(initial)
    assertUndoEquivalence(reference: reference, subject: &subject, steps: steps, file: file, line: line)
}
