import XCTest
import Foundation
import TextBuffer
import TextBufferTesting

@MainActor
final class UndoEquivalenceDriftTests: XCTestCase {
    func `test simple insert undo redo`() {
        assertUndoEquivalence(initial: "abc", steps: [
            .insert(content: "X", at: 0),
            .undo,
            .redo,
        ])
    }

    func `test delete then undo`() {
        assertUndoEquivalence(initial: "abc", steps: [
            .delete(range: NSRange(location: 0, length: 1)),
            .undo,
        ])
    }

    func `test replace then undo then redo`() {
        assertUndoEquivalence(initial: "abc", steps: [
            .replace(range: NSRange(location: 0, length: 3), with: "XYZ"),
            .undo,
            .redo,
        ])
    }

    func `test grouped operations undo redo`() {
        assertUndoEquivalence(initial: "", steps: [
            .group(actionName: nil, steps: [
                .insert(content: "A", at: 0),
                .insert(content: "B", at: 1),
            ]),
            .undo,
            .redo,
        ])
    }

    func `test interleaved edits and undos`() {
        assertUndoEquivalence(initial: "", steps: [
            .insert(content: "A", at: 0),
            .insert(content: "B", at: 1),
            .undo,
            .insert(content: "C", at: 1),
            .undo,
            .undo,
        ])
    }

    func `test redo tail truncation`() {
        assertUndoEquivalence(initial: "", steps: [
            .insert(content: "A", at: 0),
            .undo,
            .insert(content: "B", at: 0),
            .redo,
        ])
    }

    func `test selection state at every step`() {
        assertUndoEquivalence(initial: "hello", steps: [
            .select(NSRange(location: 0, length: 5)),
            .insert(content: "X", at: 0),
            .undo,
            .select(NSRange(location: 2, length: 0)),
            .redo,
        ])
    }
}
