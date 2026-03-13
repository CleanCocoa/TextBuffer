## Why

The OperationLog is the foundation for `TransferableUndoable<Base>` — the value-type undo/redo engine that enables O(1) buffer transfer (ADR-002). Before any higher-level undo wrapper or buffer transfer can be built, the core recording and replay types must exist. This change implements TASK-003 and TASK-004 from the Milestone 1 roadmap (Phase 2: Core Value Types).

## What Changes

- Introduce `BufferOperation` value type with `Kind` enum (`insert`, `delete`, `replace`) representing a single reversible mutation.
- Introduce `UndoGroup` value type holding an ordered list of `BufferOperation`s plus selection metadata (`selectionBefore`, `selectionAfter`) and an optional `actionName` (ADR-008, ADR-009).
- Introduce `OperationLog` value type implementing:
  - History array + cursor model for undo/redo navigation
  - Grouping stack for nested `beginUndoGroup`/`endUndoGroup` with merge semantics
  - `record(_:)` to append operations to the current open group
  - `undo(on:)` / `redo(on:)` generic over `Buffer`, applying inverse/forward operations and restoring exact selection state
  - Redo tail truncation on new edits after undo
  - `preconditionFailure` on recording outside a group or on inverse-operation failure

## Capabilities

### New Capabilities
- `operation-log-types`: BufferOperation, UndoGroup, and OperationLog value types — recording, grouping, undo/redo mechanics

### Modified Capabilities
<!-- None — this is greenfield. -->

## Impact

- **New files:**
  - `Sources/TextBuffer/OperationLog/BufferOperation.swift`
  - `Sources/TextBuffer/OperationLog/UndoGroup.swift`
  - `Sources/TextBuffer/OperationLog/OperationLog.swift`
  - `Tests/TextBufferTests/OperationLogTests.swift`
- **APIs added:** `BufferOperation`, `UndoGroup`, `OperationLog` — all public, `Sendable`, `Equatable`
- **Dependencies:** `OperationLog.undo(on:)`/`redo(on:)` are generic over the `Buffer` protocol (TASK-001, already landed)
- **Downstream:** TASK-005 (`TransferableUndoable`) depends directly on these types
