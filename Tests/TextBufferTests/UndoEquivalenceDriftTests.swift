import XCTest
import Foundation
import TextBuffer
import TextBufferTesting

@MainActor
final class UndoEquivalenceDriftTests: XCTestCase {
    func testSimpleInsertUndoRedo() {
        assertUndoEquivalence(initial: "abc", steps: [
            .insert(content: "X", at: 0),
            .undo,
            .redo,
        ])
    }

    func testDeleteThenUndo() {
        assertUndoEquivalence(initial: "abc", steps: [
            .select(NSRange(location: 1, length: 0)),
            .delete(range: NSRange(location: 0, length: 1)),
            .undo,
        ])
    }

    func testReplaceThenUndoThenRedo() {
        XCTExpectFailure("Undoable (NSUndoManager) does not restore selection on undo; TransferableUndoable (OperationLog) does")
        assertUndoEquivalence(initial: "abc", steps: [
            .replace(range: NSRange(location: 0, length: 3), with: "XYZ"),
            .undo,
            .redo,
        ])
    }

    func testGroupedOperationsUndoRedo() {
        assertUndoEquivalence(initial: "", steps: [
            .group(actionName: nil, steps: [
                .insert(content: "A", at: 0),
                .insert(content: "B", at: 1),
            ]),
            .undo,
            .redo,
        ])
    }

    func testInterleavedEditsAndUndos() {
        assertUndoEquivalence(initial: "", steps: [
            .insert(content: "A", at: 0),
            .insert(content: "B", at: 1),
            .undo,
            .insert(content: "C", at: 1),
            .undo,
            .undo,
        ])
    }

    func testRedoTailTruncation() {
        assertUndoEquivalence(initial: "", steps: [
            .insert(content: "A", at: 0),
            .undo,
            .insert(content: "B", at: 0),
            .redo,
        ])
    }

    func testSelectionStateAtEveryStep() {
        XCTExpectFailure("Undoable (NSUndoManager) does not restore selection on undo; TransferableUndoable (OperationLog) does")
        assertUndoEquivalence(initial: "hello", steps: [
            .select(NSRange(location: 0, length: 5)),
            .insert(content: "X", at: 0),
            .undo,
            .select(NSRange(location: 2, length: 0)),
            .redo,
        ])
    }
}
