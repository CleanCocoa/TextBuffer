## 1. Test File Setup

- [ ] 1.1 Create `Tests/TextBufferTests/RopeTransferIntegrationTests.swift` with `@MainActor final class RopeTransferIntegrationTests: XCTestCase`, importing TextBuffer, TextRope, and Foundation
- [ ] 1.2 Add helper method to create a `TransferableUndoable<RopeBuffer>` from an initial string, and a parallel `TransferableUndoable<MutableStringBuffer>` from the same string, for side-by-side comparison

## 2. Undo/Redo on Rope-Backed Buffer

- [ ] 2.1 Test single insert then undo on `TransferableUndoable<RopeBuffer>` — verify content restored, `canUndo` false, `canRedo` true
- [ ] 2.2 Test grouped mutations (via `undoGrouping`) undo atomically on rope buffer
- [ ] 2.3 Test undo then redo restores state on rope buffer
- [ ] 2.4 Test undo/redo with multi-byte Unicode content (emoji U+10000+, CJK, combining marks) — no corruption at UTF-8/UTF-16 boundaries

## 3. Snapshot from Rope to String Buffer

- [ ] 3.1 Test `snapshot()` preserves content and selectedRange from `TransferableUndoable<RopeBuffer>` to `TransferableUndoable<MutableStringBuffer>`
- [ ] 3.2 Test `snapshot()` preserves undo history — calling undo on snapshot produces same content as undo on original
- [ ] 3.3 Test snapshot independence — mutations on original do not affect snapshot and vice versa
- [ ] 3.4 Test `snapshot()` with multi-byte Unicode content — byte-identical content, correct UTF-16 selectedRange

## 4. Represent from String Buffer into Rope Buffer

- [ ] 4.1 Test `represent(_:)` loads content and selectedRange into `TransferableUndoable<RopeBuffer>`
- [ ] 4.2 Test `represent(_:)` loads undo history — undo after represent replays correctly through rope buffer
- [ ] 4.3 Test `represent(_:)` replaces previous state entirely — old undo history discarded
- [ ] 4.4 Test `represent(_:)` with multi-byte Unicode content — no UTF-8/UTF-16 translation errors

## 5. Cross-Type Transfer Round-Trip

- [ ] 5.1 Test Rope → String → Rope round-trip preserves content, selection, and undo behavior
- [ ] 5.2 Test undo/redo works correctly after round-trip transfer
- [ ] 5.3 Test multiple consecutive round-trips are idempotent with respect to observable state

## 6. Undo Equivalence Across Buffer Types

- [ ] 6.1 Test simple edit sequence (insert, delete, replace) produces identical content and selectedRange on both `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>` after every step
- [ ] 6.2 Test undo/redo interleaved with edits produces identical state on both buffer types after every step
- [ ] 6.3 Test grouped operations produce identical state on both buffer types, with atomic undo
- [ ] 6.4 Test multi-byte Unicode edit sequences produce identical state on both buffer types — confirms UTF-8/UTF-16 consistency

## 7. Three Buffer Types Interchangeable

- [ ] 7.1 Test RopeBuffer snapshot consumed by MutableStringBuffer represent — identical content, selection, undo history
- [ ] 7.2 Test MutableStringBuffer snapshot consumed by RopeBuffer represent — identical content, selection, undo history
- [ ] 7.3 Test three-way exchange: Rope → snapshot → String (mutate) → snapshot → Rope — final state reflects all mutations with full undo history
