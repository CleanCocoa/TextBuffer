## Context

This change covers TASKS.md Phase 1 (TASK-001, TASK-002) — the test infrastructure that must exist before any Milestone 1 production code. TextBufferTesting already provides `assertBufferState` and `makeBuffer` helpers. This change adds `BufferStep` and `assertUndoEquivalence` to that module, plus guarded integration tests in TextBufferTests.

The key challenge: `TransferableUndoable` does not exist yet (TASK-005). The test helpers must compile now but defer actual use until the type is available. SPEC.md §4.4 defines the exact type signatures and enum cases.

## Goals / Non-Goals

**Goals:**
- Establish `BufferStep` enum covering all buffer operation cases per SPEC.md §4.4
- Implement `assertUndoEquivalence` function structure that will drive equivalence drift testing (TASK-006)
- Document three transfer integration scenarios (transfer-out, transfer-in, transitivity) as guarded test stubs
- All files compile with guards in place; `swift test` passes with no new failures

**Non-Goals:**
- Implementing `TransferableUndoable`, `OperationLog`, or any production types (TASK-003 through TASK-005)
- Making `assertUndoEquivalence` actually runnable — it will be guarded until TASK-005/TASK-006
- Writing passing equivalence tests — those belong to TASK-006
- Completing integration tests — those are finalized in TASK-009

## Decisions

### D1: Guard strategy for forward-referencing TransferableUndoable

**Decision:** Use `#if false` compiler guards around code that references `TransferableUndoable`.

**Rationale:** `TransferableUndoable` is delivered by TASK-005. Using `#if false` is simpler than introducing a stub/protocol — the guards are removed wholesale in TASK-006 when the real type arrives. This matches the approach noted in TASK-001's description.

**Alternative considered:** Creating a minimal stub type. Rejected because it would need to conform to `Buffer` and support undo, duplicating work that TASK-005 does properly.

### D2: BufferStep as recursive enum

**Decision:** `BufferStep.group` contains `steps: [BufferStep]` (indirect/recursive) rather than flat `beginGroup`/`endGroup` cases.

**Rationale:** SPEC.md §8 explicitly states this convention — the recursive case maps directly to the closure-based `undoGrouping { }` API on both `Undoable` and `TransferableUndoable`. A flat model would require stack tracking in the assertion function.

### D3: Integration test structure

**Decision:** Three test methods in `TransferIntegrationTests`, each wrapped in `#if false`. Each test documents its scenario in comments and defines the step sequence it will execute once unguarded in TASK-009.

**Rationale:** Writing the tests now forces early validation of the transfer scenarios from SPEC.md §4.2 (snapshot/represent). The scenarios map directly to TASK-002's acceptance criteria (Test A, Test B, Test C).

### D4: Equivalence testing as the primary correctness mechanism

`assertUndoEquivalence` is not merely a convenience helper — it is the **primary guard against behavioral drift** for the entire Milestone 1. `Undoable<MutableStringBuffer>` (backed by `NSUndoManager`) serves as the behavioral oracle: if the operation log diverges from `NSUndoManager`'s semantics in any scenario, the drift test catches it. This strategic role justifies building the test infrastructure first (before any production types exist) and is why this is Phase 1.

The equivalence tests also guard against a specific production risk: `OperationLog.undo(on:)` uses `preconditionFailure` if an inverse operation fails. Such failures can only occur if the recording logic captured an operation inconsistent with what the buffer actually did. The equivalence tests exercise every edit/undo/redo path, surfacing recording bugs before they become production crashes.

## Risks / Trade-offs

- **[Risk] Guard rot** — Guarded code may drift from the eventual API. → Mitigated by TASK-006 and TASK-009 which unguard and must compile. The gap is short (3-4 tasks).
- **[Risk] BufferStep enum may need additional cases** — Future milestones could add operations. → The enum is non-frozen and in the testing module, so adding cases is non-breaking.
