import Foundation
import XCTest
import TextBuffer

#if false
private func applyStep(_ step: BufferStep, to buffer: Undoable<MutableStringBuffer>) {
    switch step {
    case .insert(let content, let at):
        try? buffer.insert(content, at: at)
    case .delete(let range):
        try? buffer.delete(in: range)
    case .replace(let range, let with):
        try? buffer.replace(range: range, with: with)
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

public func assertUndoEquivalence(
    reference: Undoable<MutableStringBuffer>,
    subject: TransferableUndoable<MutableStringBuffer>,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    for step in steps {
        applyStep(step, to: reference)
    }
    XCTAssertEqual(reference.content, subject.content, file: file, line: line)
    XCTAssertEqual(reference.selectedRange, subject.selectedRange, file: file, line: line)
}

public func assertUndoEquivalence(
    initial: String,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
) {
    let reference = Undoable(MutableStringBuffer(initial))
    let subject = TransferableUndoable(MutableStringBuffer(initial))
    assertUndoEquivalence(
        reference: reference,
        subject: subject,
        steps: steps,
        file: file,
        line: line
    )
}
#endif
