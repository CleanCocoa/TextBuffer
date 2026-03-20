import XCTest
import TextBuffer
import TextBufferTesting

@MainActor
final class SendableRopeBufferUndoEquivalenceTests: XCTestCase {

    func testInsertThenUndo() {
        assertSendableUndoEquivalence(
            initial: "hello",
            steps: [
                .insert(content: "X", at: 0),
                .undo,
            ]
        )
    }

    func testDeleteThenUndoRedo() {
        assertSendableUndoEquivalence(
            initial: "hello world",
            steps: [
                .delete(range: NSRange(location: 5, length: 6)),
                .undo,
                .redo,
            ]
        )
    }

    func testReplaceThenUndoRedoUndo() {
        assertSendableUndoEquivalence(
            initial: "hello world",
            steps: [
                .replace(range: NSRange(location: 0, length: 5), with: "howdy"),
                .undo,
                .redo,
                .undo,
            ]
        )
    }

    func testGroupedOperationsThenUndo() {
        assertSendableUndoEquivalence(
            initial: "",
            steps: [
                .group(actionName: "batch", steps: [
                    .insert(content: "hello", at: 0),
                    .insert(content: " world", at: 5),
                ]),
                .undo,
            ]
        )
    }

    func testEmojiInsertDeleteUndo() {
        assertSendableUndoEquivalence(
            initial: "🎉",
            steps: [
                .insert(content: "🎊", at: 2),
                .delete(range: NSRange(location: 0, length: 2)),
                .undo,
                .undo,
            ]
        )
    }

    func testCJKReplaceUndo() {
        assertSendableUndoEquivalence(
            initial: "你好世界",
            steps: [
                .replace(range: NSRange(location: 0, length: 2), with: "再见"),
                .undo,
            ]
        )
    }

    func testMultipleOperationsThenUndoAll() {
        assertSendableUndoEquivalence(
            initial: "abc",
            steps: [
                .insert(content: "X", at: 0),
                .insert(content: "Y", at: 2),
                .delete(range: NSRange(location: 0, length: 1)),
                .undo,
                .undo,
                .undo,
            ]
        )
    }
}
