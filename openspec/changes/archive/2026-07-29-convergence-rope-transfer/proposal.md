## Why

SPEC.md defines two structurally independent milestones that converge when `TransferableUndoable<RopeBuffer>` is verified (TASK-021). Milestone 1 delivers the operation-log-backed undo/transfer system; Milestone 2 delivers the rope-backed buffer. Neither milestone proves they compose correctly until integration tests confirm that undo/redo, `snapshot()`, and `represent(_:)` work across all three buffer types (`MutableStringBuffer`, `RopeBuffer`, `NSTextViewBuffer`-equivalent via `MutableStringBuffer` proxy). This change is the convergence point — it validates the architectural bet that `TransferableUndoable<Base>` is truly generic over any `Buffer` conformer.

Corresponds to **TASK-021** (Convergence) in TASKS.md. Depends on TASK-008 (TransferableUndoable complete), TASK-018 (RopeBuffer conformance), and TASK-020 (RopeBuffer drift tests passing).

## What Changes

- Add `RopeTransferIntegrationTests.swift` — integration tests proving `TransferableUndoable<RopeBuffer>` correctness:
  - Undo/redo on a rope-backed buffer produces correct content and selection
  - `snapshot()` from `TransferableUndoable<RopeBuffer>` yields an independent `TransferableUndoable<MutableStringBuffer>` with identical state
  - `represent(_:)` loads a `TransferableUndoable<MutableStringBuffer>` snapshot into a `TransferableUndoable<RopeBuffer>`, preserving content, selection, and undo history
  - Undo equivalence: identical `BufferStep` sequences produce identical results regardless of whether the underlying buffer is `MutableStringBuffer` or `RopeBuffer`
- Verify three buffer types are interchangeable via the transfer API (snapshot/represent round-trips)

## Capabilities

### New Capabilities
- `rope-transfer-convergence`: TransferableUndoable<RopeBuffer> correctness — undo/redo on rope-backed buffers, cross-type snapshot/represent, three buffer types interchangeable via the transfer API, undo equivalence across buffer types

### Modified Capabilities
<!-- None — this change adds integration tests over existing APIs without modifying any requirements. -->

## Impact

- **Files**: `Tests/TextBufferTests/RopeTransferIntegrationTests.swift` (new)
- **Dependencies**: Requires all Milestone 1 types (OperationLog, TransferableUndoable, BufferStep, assertUndoEquivalence) and Milestone 2 types (TextRope, RopeBuffer) to be implemented
- **APIs**: No new public API — this change exercises existing APIs in combination
- **Risk**: Low — pure test code with no production changes; validates existing contracts
