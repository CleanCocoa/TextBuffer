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

    func testRopeToStringToRopeRoundTripPreservesState() {
        let original = TransferableUndoable(RopeBuffer("émigré"))
        try! original.insert(" 你好", at: 6)
        original.select(NSRange(location: 7, length: 2))

        let intermediate: TransferableUndoable<MutableStringBuffer> = original.snapshot()
        let roundTripped = TransferableUndoable(RopeBuffer(""))
        roundTripped.represent(intermediate)

        XCTAssertEqual(roundTripped.content, "émigré 你好")
        XCTAssertEqual(roundTripped.selectedRange, NSRange(location: 7, length: 2))

        original.undo()
        roundTripped.undo()
        XCTAssertEqual(roundTripped.content, original.content)
        XCTAssertEqual(roundTripped.selectedRange, original.selectedRange)
    }

    func testUndoRedoAfterRoundTripTransfer() {
        let original = TransferableUndoable(RopeBuffer("abc"))
        try! original.insert("X", at: 0)
        try! original.insert("Y", at: 4)

        let roundTripped = TransferableUndoable(RopeBuffer(""))
        roundTripped.represent(original.snapshot())

        roundTripped.undo()
        XCTAssertEqual(roundTripped.content, "Xabc")
        roundTripped.undo()
        XCTAssertEqual(roundTripped.content, "abc")
        XCTAssertFalse(roundTripped.canUndo)

        roundTripped.redo()
        XCTAssertEqual(roundTripped.content, "Xabc")
        roundTripped.redo()
        XCTAssertEqual(roundTripped.content, "XabcY")
        XCTAssertFalse(roundTripped.canRedo)
    }

    func testConsecutiveRoundTripsAreIdempotent() {
        let buffer = TransferableUndoable(RopeBuffer("stable état"))
        try! buffer.insert("!", at: 11)
        buffer.select(NSRange(location: 0, length: 6))
        buffer.undo()

        for iteration in 1...3 {
            let before = (buffer.content, buffer.selectedRange, buffer.canUndo, buffer.canRedo)

            let receiver = TransferableUndoable(RopeBuffer(""))
            receiver.represent(buffer.snapshot())

            XCTAssertEqual(receiver.content, before.0, "content changed on round-trip \(iteration)")
            XCTAssertEqual(receiver.selectedRange, before.1, "selection changed on round-trip \(iteration)")
            XCTAssertEqual(receiver.canUndo, before.2, "canUndo changed on round-trip \(iteration)")
            XCTAssertEqual(receiver.canRedo, before.3, "canRedo changed on round-trip \(iteration)")
        }
    }

    func testInterleavedEditsAndUndoRedoMatchAcrossBufferTypes() {
        let pair = makeBufferPair("départ")

        try! pair.rope.insert("A", at: 0)
        try! pair.msb.insert("A", at: 0)
        assertPairMatch(pair, "insert A")

        pair.rope.undo()
        pair.msb.undo()
        assertPairMatch(pair, "undo insert A")

        try! pair.rope.insert("B", at: 6)
        try! pair.msb.insert("B", at: 6)
        assertPairMatch(pair, "insert B after undo")

        try! pair.rope.delete(in: NSRange(location: 1, length: 2))
        try! pair.msb.delete(in: NSRange(location: 1, length: 2))
        assertPairMatch(pair, "delete")

        pair.rope.undo()
        pair.msb.undo()
        assertPairMatch(pair, "undo delete")

        pair.rope.redo()
        pair.msb.redo()
        assertPairMatch(pair, "redo delete")

        try! pair.rope.replace(range: NSRange(location: 0, length: 1), with: "ç")
        try! pair.msb.replace(range: NSRange(location: 0, length: 1), with: "ç")
        assertPairMatch(pair, "replace after redo")

        pair.rope.undo()
        pair.msb.undo()
        assertPairMatch(pair, "final undo")
    }

    func testGroupedOperationsMatchAcrossBufferTypesWithAtomicUndo() {
        let pair = makeBufferPair("naïve")

        pair.rope.undoGrouping {
            try! pair.rope.insert("«", at: 0)
            try! pair.rope.insert("»", at: 6)
        }
        pair.msb.undoGrouping {
            try! pair.msb.insert("«", at: 0)
            try! pair.msb.insert("»", at: 6)
        }
        assertPairMatch(pair, "grouped inserts")
        XCTAssertEqual(pair.rope.log.undoableCount, pair.msb.log.undoableCount)

        pair.rope.undo()
        pair.msb.undo()
        assertPairMatch(pair, "atomic undo of group")
        XCTAssertEqual(pair.rope.content, "naïve")
    }

    func testRopeSnapshotConsumedByStringBufferRepresent() {
        let rope = TransferableUndoable(RopeBuffer("løg"))
        try! rope.insert("bog", at: 3)
        rope.select(NSRange(location: 0, length: 3))

        let receiver = TransferableUndoable(MutableStringBuffer(""))
        receiver.represent(rope.snapshot())

        XCTAssertEqual(receiver.content, "løgbog")
        XCTAssertEqual(receiver.selectedRange, NSRange(location: 0, length: 3))

        receiver.undo()
        XCTAssertEqual(receiver.content, "løg")
        XCTAssertFalse(receiver.canUndo)
    }

    func testStringBufferSnapshotConsumedByRopeBufferRepresent() {
        let msb = TransferableUndoable(MutableStringBuffer("løg"))
        try! msb.insert("bog", at: 3)
        msb.select(NSRange(location: 3, length: 3))

        let receiver = TransferableUndoable(RopeBuffer(""))
        receiver.represent(msb.snapshot())

        XCTAssertEqual(receiver.content, "løgbog")
        XCTAssertEqual(receiver.selectedRange, NSRange(location: 3, length: 3))

        receiver.undo()
        XCTAssertEqual(receiver.content, "løg")
        XCTAssertFalse(receiver.canUndo)
    }

    func testThreeWayExchangeReflectsAllMutationsWithFullHistory() {
        let rope = TransferableUndoable(RopeBuffer("start"))
        try! rope.insert(" 一", at: 5)

        let string = TransferableUndoable(MutableStringBuffer(""))
        string.represent(rope.snapshot())
        try! string.insert(" 二", at: 7)

        let finalRope = TransferableUndoable(RopeBuffer(""))
        finalRope.represent(string.snapshot())

        XCTAssertEqual(finalRope.content, "start 一 二")

        finalRope.undo()
        XCTAssertEqual(finalRope.content, "start 一")
        finalRope.undo()
        XCTAssertEqual(finalRope.content, "start")
        XCTAssertFalse(finalRope.canUndo)

        finalRope.redo()
        finalRope.redo()
        XCTAssertEqual(finalRope.content, "start 一 二")
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
