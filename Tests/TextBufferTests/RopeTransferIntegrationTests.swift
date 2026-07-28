import XCTest
import Foundation
import TextBuffer
import TextBufferTesting

@MainActor
final class RopeTransferIntegrationTests: XCTestCase {
    private func makeBufferPair(_ content: String) -> (rope: TransferableUndoable<RopeBuffer>, msb: TransferableUndoable<MutableStringBuffer>) {
        (TransferableUndoable(RopeBuffer(content)), TransferableUndoable(MutableStringBuffer(content)))
    }

    private func assertPairMatch(
        _ pair: (rope: TransferableUndoable<RopeBuffer>, msb: TransferableUndoable<MutableStringBuffer>),
        _ step: String,
        file: StaticString = #filePath, line: UInt = #line
    ) {
        XCTAssertEqual(pair.rope.content, pair.msb.content, "content diverged: \(step)", file: file, line: line)
        XCTAssertEqual(pair.rope.selectedRange, pair.msb.selectedRange, "selection diverged: \(step)", file: file, line: line)
    }

    func testSingleInsertThenUndoOnRopeBuffer() {
        let buffer = TransferableUndoable(RopeBuffer("hello"))
        try! buffer.insert("X", at: 5)
        XCTAssertEqual(buffer.content, "helloX")
        XCTAssertTrue(buffer.canUndo)

        buffer.undo()

        XCTAssertEqual(buffer.content, "hello")
        XCTAssertFalse(buffer.canUndo)
        XCTAssertTrue(buffer.canRedo)
    }

    func testUndoThenRedoRestoresStateOnRopeBuffer() {
        let buffer = TransferableUndoable(RopeBuffer("base"))
        buffer.select(NSRange(location: 4, length: 0))
        try! buffer.insert("ment", at: 4)
        XCTAssertEqual(buffer.content, "basement")

        buffer.undo()
        XCTAssertEqual(buffer.content, "base")

        buffer.redo()
        XCTAssertEqual(buffer.content, "basement")
        XCTAssertTrue(buffer.canUndo)
        XCTAssertFalse(buffer.canRedo)
    }

    func testSnapshotPreservesContentAndSelection() {
        let rope = TransferableUndoable(RopeBuffer("hello world"))
        rope.select(NSRange(location: 6, length: 5))

        let snap: TransferableUndoable<MutableStringBuffer> = rope.snapshot()

        XCTAssertEqual(snap.content, "hello world")
        XCTAssertEqual(snap.selectedRange, NSRange(location: 6, length: 5))
    }

    func testRepresentLoadsContentAndSelectionIntoRopeBuffer() {
        let source = TransferableUndoable(MutableStringBuffer("données"))
        source.select(NSRange(location: 3, length: 2))

        let receiver = TransferableUndoable(RopeBuffer("stale"))
        receiver.represent(source)

        XCTAssertEqual(receiver.content, "données")
        XCTAssertEqual(receiver.selectedRange, NSRange(location: 3, length: 2))
    }

    func testRepresentDiscardsPreviousStateAndHistory() {
        let receiver = TransferableUndoable(RopeBuffer("old"))
        try! receiver.insert("!", at: 3)
        XCTAssertEqual(receiver.content, "old!")
        XCTAssertTrue(receiver.canUndo)

        let source = TransferableUndoable(MutableStringBuffer("new"))
        try! source.insert("?", at: 3)

        receiver.represent(source)
        XCTAssertEqual(receiver.content, "new?")

        receiver.undo()
        XCTAssertEqual(receiver.content, "new")
        XCTAssertFalse(receiver.canUndo)
    }

    func testUndoRedoOnRopeBuffer() {
        let buffer = TransferableUndoable(RopeBuffer("hello"))
        try! buffer.insert(" world", at: 5)
        XCTAssertEqual(buffer.content, "hello world")

        buffer.undo()
        XCTAssertEqual(buffer.content, "hello")

        buffer.redo()
        XCTAssertEqual(buffer.content, "hello world")
    }

    func testGroupedUndoOnRopeBuffer() {
        let buffer = TransferableUndoable(RopeBuffer(""))
        buffer.undoGrouping {
            try! buffer.insert("A", at: 0)
            try! buffer.insert("B", at: 1)
        }
        XCTAssertEqual(buffer.content, "AB")
        XCTAssertEqual(buffer.log.undoableCount, 1)

        buffer.undo()
        XCTAssertEqual(buffer.content, "")
    }

    func testSnapshotFromRopeBufferToMutableStringBuffer() {
        let buffer = TransferableUndoable(RopeBuffer("hello"))
        try! buffer.insert("X", at: 0)
        XCTAssertEqual(buffer.content, "Xhello")

        let snap = buffer.snapshot()
        XCTAssertEqual(snap.content, "Xhello")
        XCTAssertTrue(snap.canUndo)

        snap.undo()
        XCTAssertEqual(snap.content, "hello")
    }

    func testRepresentFromMutableStringBufferIntoRopeBuffer() {
        let source = TransferableUndoable(MutableStringBuffer("data"))
        try! source.insert("!", at: 4)
        try! source.insert("?", at: 5)
        XCTAssertEqual(source.content, "data!?")

        let receiver = TransferableUndoable(RopeBuffer(""))
        receiver.represent(source)
        XCTAssertEqual(receiver.content, "data!?")

        receiver.undo()
        XCTAssertEqual(receiver.content, "data!")
        receiver.undo()
        XCTAssertEqual(receiver.content, "data")
    }

    func testSnapshotThenRepresentRoundTrip() {
        let rope = TransferableUndoable(RopeBuffer("base"))
        try! rope.insert("X", at: 4)
        XCTAssertEqual(rope.content, "baseX")

        let snap = rope.snapshot()
        try! snap.insert("Y", at: 5)
        XCTAssertEqual(snap.content, "baseXY")

        rope.represent(snap)
        XCTAssertEqual(rope.content, "baseXY")

        rope.undo()
        XCTAssertEqual(rope.content, "baseX")
        rope.undo()
        XCTAssertEqual(rope.content, "base")
    }

    func testSnapshotIndependence() {
        let rope = TransferableUndoable(RopeBuffer("original"))
        try! rope.insert("!", at: 8)
        let snap = rope.snapshot()

        try! rope.insert("?", at: 9)
        XCTAssertEqual(rope.content, "original!?")
        XCTAssertEqual(snap.content, "original!")

        try! snap.insert("Z", at: 0)
        XCTAssertEqual(snap.content, "Zoriginal!")
        XCTAssertEqual(rope.content, "original!?")
    }

    func testUndoRedoWithMultiByteContentOnRopeBuffer() {
        let buffer = TransferableUndoable(RopeBuffer("😀你好"))

        try! buffer.insert("𝄞", at: 2)
        XCTAssertEqual(buffer.content, "😀𝄞你好")

        try! buffer.insert("e\u{0301}", at: 6)
        XCTAssertEqual(buffer.content, "😀𝄞你好e\u{0301}")

        try! buffer.delete(in: NSRange(location: 0, length: 2))
        XCTAssertEqual(buffer.content, "𝄞你好e\u{0301}")

        try! buffer.replace(range: NSRange(location: 2, length: 2), with: "🎉")
        XCTAssertEqual(buffer.content, "𝄞🎉e\u{0301}")

        buffer.undo()
        XCTAssertEqual(buffer.content, "𝄞你好e\u{0301}")
        buffer.undo()
        XCTAssertEqual(buffer.content, "😀𝄞你好e\u{0301}")
        buffer.undo()
        XCTAssertEqual(buffer.content, "😀𝄞你好")
        buffer.undo()
        XCTAssertEqual(buffer.content, "😀你好")

        buffer.redo()
        XCTAssertEqual(buffer.content, "😀𝄞你好")
        buffer.redo()
        XCTAssertEqual(buffer.content, "😀𝄞你好e\u{0301}")
        buffer.redo()
        XCTAssertEqual(buffer.content, "𝄞你好e\u{0301}")
        buffer.redo()
        XCTAssertEqual(buffer.content, "𝄞🎉e\u{0301}")
    }

    func testSnapshotWithMultiByteContent() {
        let rope = TransferableUndoable(RopeBuffer("a😀你e\u{0301}b"))
        try! rope.insert("🎉", at: 3)
        XCTAssertEqual(rope.content, "a😀🎉你e\u{0301}b")
        rope.select(NSRange(location: 1, length: 4))

        let snap = rope.snapshot()
        XCTAssertEqual(snap.content, rope.content)
        XCTAssertEqual(Array(snap.content.utf8), Array(rope.content.utf8))
        XCTAssertEqual(snap.selectedRange, NSRange(location: 1, length: 4))

        snap.undo()
        XCTAssertEqual(snap.content, "a😀你e\u{0301}b")
        XCTAssertEqual(Array(snap.content.utf8), Array("a😀你e\u{0301}b".utf8))
        XCTAssertEqual(rope.content, "a😀🎉你e\u{0301}b")
    }

    func testRepresentWithMultiByteContent() {
        let source = TransferableUndoable(MutableStringBuffer("你好"))
        try! source.insert("😀", at: 2)
        try! source.insert("e\u{0301}", at: 4)
        XCTAssertEqual(source.content, "你好😀e\u{0301}")
        source.select(NSRange(location: 2, length: 2))

        let receiver = TransferableUndoable(RopeBuffer(""))
        receiver.represent(source)
        XCTAssertEqual(receiver.content, "你好😀e\u{0301}")
        XCTAssertEqual(Array(receiver.content.utf8), Array(source.content.utf8))
        XCTAssertEqual(receiver.selectedRange, NSRange(location: 2, length: 2))

        receiver.undo()
        XCTAssertEqual(receiver.content, "你好😀")
        receiver.undo()
        XCTAssertEqual(receiver.content, "你好")
    }

    func testMultiByteUndoEquivalenceAcrossBufferTypes() {
        let msb = TransferableUndoable(MutableStringBuffer("a你b"))
        let rb = TransferableUndoable(RopeBuffer("a你b"))

        try! msb.insert("😀", at: 1)
        try! rb.insert("😀", at: 1)
        XCTAssertEqual(msb.content, rb.content, "after emoji insert")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after emoji insert")

        try! msb.insert("e\u{0301}", at: 5)
        try! rb.insert("e\u{0301}", at: 5)
        XCTAssertEqual(msb.content, rb.content, "after combining-mark insert")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after combining-mark insert")

        try! msb.delete(in: NSRange(location: 1, length: 2))
        try! rb.delete(in: NSRange(location: 1, length: 2))
        XCTAssertEqual(msb.content, rb.content, "after surrogate-pair delete")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after surrogate-pair delete")

        try! msb.replace(range: NSRange(location: 1, length: 1), with: "𝕳")
        try! rb.replace(range: NSRange(location: 1, length: 1), with: "𝕳")
        XCTAssertEqual(msb.content, rb.content, "after CJK-to-emoji replace")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after CJK-to-emoji replace")

        msb.undo()
        rb.undo()
        XCTAssertEqual(msb.content, rb.content, "after undo")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after undo")

        msb.undo()
        rb.undo()
        XCTAssertEqual(msb.content, rb.content, "after second undo")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after second undo")

        msb.redo()
        rb.redo()
        XCTAssertEqual(msb.content, rb.content, "after redo")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after redo")

        XCTAssertEqual(Array(msb.content.utf8), Array(rb.content.utf8), "byte-identical after redo")
    }

    func testUndoEquivalenceAcrossBufferTypes() {
        let msb = TransferableUndoable(MutableStringBuffer("abc"))
        let rb = TransferableUndoable(RopeBuffer("abc"))

        try! msb.insert("X", at: 0)
        try! rb.insert("X", at: 0)
        XCTAssertEqual(msb.content, rb.content, "after insert")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after insert")

        try! msb.delete(in: NSRange(location: 1, length: 2))
        try! rb.delete(in: NSRange(location: 1, length: 2))
        XCTAssertEqual(msb.content, rb.content, "after delete")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after delete")

        try! msb.replace(range: NSRange(location: 0, length: 1), with: "YZ")
        try! rb.replace(range: NSRange(location: 0, length: 1), with: "YZ")
        XCTAssertEqual(msb.content, rb.content, "after replace")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after replace")

        msb.undo()
        rb.undo()
        XCTAssertEqual(msb.content, rb.content, "after undo")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after undo")

        msb.redo()
        rb.redo()
        XCTAssertEqual(msb.content, rb.content, "after redo")
        XCTAssertEqual(msb.selectedRange, rb.selectedRange, "selection after redo")
    }
}
