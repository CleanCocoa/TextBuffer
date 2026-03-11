## Why

`TextRope` exists as a fully-tested data structure but is not yet accessible through the `Buffer` protocol, meaning no editor or undo system can use it. This change exposes `TextRope` via a `RopeBuffer` conformer, proves it is behaviorally equivalent to `MutableStringBuffer` through drift testing, then verifies that `TransferableUndoable<RopeBuffer>` composes correctly — confirming that both milestones converge as designed.

## What Changes

- **New `RopeBuffer` type** — `Buffer`-conforming wrapper around `TextRope`, adding `selectedRange` tracking. Same selection-adjustment semantics as `MutableStringBuffer` (shift on insert, subtract on delete).
- **New `RopeBuffer` unit tests** — basic operations: insert, delete, replace, selection adjustment, empty-buffer edge cases.
- **New `RopeBuffer` drift test suite** — ports `BufferBehaviorDriftTests` to run identical operation sequences on `RopeBuffer` and `MutableStringBuffer`, asserting equivalence after every step.
- **New convergence integration tests** — verifies `TransferableUndoable<RopeBuffer>` for undo/redo correctness, `snapshot()` from rope-backed to string-backed buffer, `represent()` in the opposite direction, and full undo equivalence across buffer types.

## Capabilities

### New Capabilities

- `rope-buffer`: `RopeBuffer` as a `Buffer`-conforming wrapper over `TextRope`, with selection adjustment parity to `MutableStringBuffer` and `TextAnalysisCapable` conformance.
- `rope-transfer-convergence`: `TransferableUndoable<RopeBuffer>` interoperating with `TransferableUndoable<MutableStringBuffer>` via `snapshot()` and `represent()`, proving buffer-type interchangeability.

### Modified Capabilities

## Impact

- **New file:** `Sources/TextBuffer/Buffer/RopeBuffer.swift`
- **New files:** `Tests/TextBufferTests/RopeBufferTests.swift`, `RopeBufferDriftTests.swift`, `RopeTransferIntegrationTests.swift`
- **Depends on:** `TextRope` (TASK-017 complete), `TransferableUndoable` with transfer API (TASK-008 complete)
- **No API breakage.** `RopeBuffer` is additive. Existing `MutableStringBuffer`, `NSTextViewBuffer`, and `Undoable` are untouched.
