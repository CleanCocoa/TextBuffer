## Context

This change implements Phase 3 of the Milestone 1 roadmap (TASK-005, TASK-006). The `OperationLog` value-type undo stack is already in place (TASK-003/004). `TransferableUndoable<Base>` is the decorator that wraps any `Buffer` with `OperationLog`-backed undo/redo, creating the foundation for buffer transfer (snapshot/represent, delivered later in TASK-008).

The existing `Undoable<Base>` uses `NSUndoManager` internally and cannot transfer undo history. Per ADR-001, both types coexist: `Undoable` serves as the behavioral gold standard for equivalence testing against `TransferableUndoable`.

## Goals / Non-Goals

**Goals:**
- `TransferableUndoable<Base>` conforms to `Buffer` with all mutations recorded to an internal `OperationLog`
- Auto-grouping ensures every mutation is wrapped in an undo group even without explicit `undoGrouping` calls
- Nestable `undoGrouping` groups multiple mutations as a single undo step
- `undo()`/`redo()` apply inverse/forward operations on the base buffer and restore selection state
- `assertUndoEquivalence` testing harness in `TextBufferTesting` enables step-by-step behavioral comparison
- Equivalence drift tests prove `TransferableUndoable ≡ Undoable` for all supported edit/undo/redo patterns

**Non-Goals:**
- `PuppetUndoManager` and AppKit integration (TASK-007)
- Transfer API — `snapshot()` and `represent(_:)` (TASK-008)
- `enableSystemUndoIntegration()` method
- Performance benchmarks or optimization

## Decisions

### D1: TransferableUndoable is a final class, not a struct

Per SPEC.md §4.2, `TransferableUndoable` is `@MainActor public final class`. It holds a reference-type `Base` buffer and needs stable identity for the future `PuppetUndoManagerDelegate` conformance. The internal `OperationLog` is a value type (struct), giving copy semantics for the undo history when transfer is added later. This mirrors the existing `Undoable<Base>` pattern.

### D2: Mutation recording follows the auto-group pattern from SPEC.md

Each `insert`/`delete`/`replace` checks `log.isGrouping`. If not grouping, it wraps the mutation in `beginUndoGroup`/`endUndoGroup` automatically. If already inside a `undoGrouping` block, it records directly. This ensures every mutation is always part of a group — no orphan operations.

The pattern is prescribed exactly in SPEC.md §4.2 and SHALL be followed verbatim.

### D3: undoGrouping uses a nesting counter via OperationLog's grouping stack

`undoGrouping` calls `log.beginUndoGroup` / `log.endUndoGroup`. The `OperationLog` maintains a grouping stack internally — nested groups merge into their parent. Only the outermost `endUndoGroup` commits to history. This is already built into `OperationLog` (TASK-003/004).

### D4: Undo/redo delegates entirely to OperationLog

`undo()` calls `log.undo(on: base)` which applies inverse operations and returns `selectionBefore`. `TransferableUndoable` then sets `base.selectedRange` to the returned selection. Same pattern for `redo()` with `selectionAfter`. No additional state management needed in the decorator.

### D5: Equivalence testing uses static dispatch, not protocol erasure

`assertUndoEquivalence` takes concrete `Undoable<MutableStringBuffer>` and `TransferableUndoable<MutableStringBuffer>` parameters. Both types conform to `Buffer`, but the function applies steps via direct method calls on each, not through a `any Buffer` existential. This avoids boxing overhead and keeps error messages specific to which implementation diverged.

### D6: BufferStep enum models the test vocabulary

`BufferStep` is a public enum in `TextBufferTesting` with cases for `insert`, `delete`, `replace`, `select`, `undo`, `redo`, and `group`. The `.group` case contains nested steps, enabling recursive application. This is the exact design from SPEC.md §4.4.

## Risks / Trade-offs

- **[Risk] Auto-group selection capture timing** → The `selectionBefore` is captured at the start of auto-group (before the mutation), and `selectionAfter` at the end. If a mutation throws, the group is still opened. Mitigation: use a `defer` or explicit cleanup pattern to ensure `endUndoGroup` is always called, even on error paths.
- **[Risk] Equivalence test flakiness from NSUndoManager timing** → `Undoable` relies on `NSUndoManager` which uses run-loop grouping by default. `Undoable` already sets `groupsByEvent = false`, so undo groups are explicit. Mitigation: verify the existing `Undoable` test configuration matches; both implementations must use explicit grouping for equivalence to hold.
- **[Trade-off] Two undo types in the API** → Per ADR-001, this is intentional. The cost is a larger API surface; the benefit is a behavioral oracle for correctness testing. `Undoable` will be deprecated once `TransferableUndoable` is proven.
