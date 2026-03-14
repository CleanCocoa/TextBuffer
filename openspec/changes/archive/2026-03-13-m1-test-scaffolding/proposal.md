## Why

TASKS.md Phase 1 (TASK-001, TASK-002) establishes test infrastructure before any Milestone 1 production code is written. The `BufferStep` enum and `assertUndoEquivalence` helpers are prerequisites for the equivalence drift tests (TASK-006) that gate `TransferableUndoable` correctness. High-level integration tests written now — guarded until the API exists — document the transfer scenarios up front and prevent scope drift during implementation.

## What Changes

- Add `BufferStep` enum to TextBufferTesting with cases for all buffer operations (insert, delete, replace, select, undo, redo, group).
- Add `assertUndoEquivalence` function to TextBufferTesting that runs identical step sequences on `Undoable<MutableStringBuffer>` (gold standard) and `TransferableUndoable<MutableStringBuffer>` (subject), asserting content + selection equality after each step.
- Guard `TransferableUndoable` references with `#if false` or stub types until TASK-005 delivers the real type.
- Add `TransferIntegrationTests.swift` with three guarded integration tests documenting transfer-out, transfer-in, and transitivity scenarios.

## Capabilities

### New Capabilities
- `undo-test-infrastructure`: BufferStep enum, assertUndoEquivalence helpers, and guarded transfer integration test scenarios

### Modified Capabilities
<!-- None — this change introduces test infrastructure only, no existing spec requirements change. -->

## Impact

- **New files:** `Sources/TextBufferTesting/BufferStep.swift`, `Sources/TextBufferTesting/AssertUndoEquivalence.swift`, `Tests/TextBufferTests/TransferIntegrationTests.swift`
- **Dependencies:** TextBufferTesting already depends on TextBuffer. No new package dependencies.
- **APIs:** New public types `BufferStep` and `assertUndoEquivalence` in TextBufferTesting. Both are test-only API.
- **Build:** Files must compile with guards in place. No test failures introduced.
