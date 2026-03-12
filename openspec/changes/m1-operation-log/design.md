## Context

This change implements the core value types for the OperationLog subsystem (TASK-003, TASK-004). These types are the foundation for `TransferableUndoable<Base>`, which replaces `NSUndoManager`-backed undo with a copyable, value-type undo history that enables O(1) buffer transfer (ADR-002).

The `Buffer` protocol (TASK-001) is already landed. No other dependencies exist.

## Goals / Non-Goals

**Goals:**
- Implement `BufferOperation`, `UndoGroup`, and `OperationLog` exactly as specified in SPEC.md §4.2
- Full unit test coverage for OperationLog recording, grouping, undo/redo mechanics
- All types are `Sendable`, `Equatable`, value types — copies are independent

**Non-Goals:**
- `TransferableUndoable<Base>` wrapper (TASK-005, separate change)
- `PuppetUndoManager` / AppKit bridge (TASK-007+)
- Log compaction or memory optimization (future work noted in ADR-002)
- Selection tracking in response to edits — that's the wrapper's job; the log just stores metadata

## Decisions

### 1. BufferOperation as flat enum with associated values

`BufferOperation.Kind` uses three cases (`insert`, `delete`, `replace`) with inline associated values rather than a struct-per-case or a protocol hierarchy. This matches SPEC.md §4.2 directly. Each case carries exactly the data needed to compute its inverse:
- `insert(content:at:)` → inverse is `delete(range:deletedContent:)` over the range the insert occupies
- `delete(range:deletedContent:)` → inverse is `insert(content:at:)` at `range.location`
- `replace(range:oldContent:newContent:)` → inverse is `replace` with old/new swapped

No alternatives were considered — the SPEC prescribes this shape and it's the simplest correct form.

### 2. UndoGroup selection metadata (ADR-008, ADR-009)

Each `UndoGroup` stores `selectionBefore: NSRange` and `selectionAfter: NSRange?`. Selection is group metadata, not an independent operation (ADR-008). Both undo and redo explicitly restore selection — they are proper inverses (ADR-009). `selectionAfter` is optional because it's set at group close, not group open.

### 3. OperationLog history + cursor model

The log uses a single `[UndoGroup]` array with an integer cursor. `history[0..<cursor]` = undoable groups, `history[cursor...]` = redoable groups. Undo decrements cursor, redo increments. New edits after undo truncate `history[cursor...]` (redo tail). This is the standard linear undo model.

### 4. Grouping stack for nested groups

`groupingStack: [UndoGroup]` supports recursive nesting. `beginUndoGroup` pushes; `endUndoGroup` pops. When popping:
- Stack becomes empty → top-level close: commit to history, truncate redo tail
- Stack non-empty → nested close: merge operations into parent, promote `actionName` if parent has none

`record(_:)` appends to `groupingStack.last`. Calling `record` with an empty stack is a `preconditionFailure`.

### 5. Undo/redo generic over Buffer

`undo(on:)` and `redo(on:)` are generic over `Buffer where B.Range == NSRange, B.Content == String`. This allows the same log to drive undo on `MutableStringBuffer` (tests), `NSTextViewBuffer` (production), or any future conformer. Inverse operation failures use `preconditionFailure` — if the log is correct and the buffer matches, inverses cannot fail (SPEC.md §4.2).

### 6. Test strategy

Tests use `MutableStringBuffer` as the concrete buffer. Coverage targets from TASK-004 acceptance criteria:
- Single operation undo/redo round-trip
- Multi-operation group undo/redo
- Nested groups merge into parent
- Redo tail truncation on new edit after undo
- `canUndo`/`canRedo` state transitions
- Action name propagation (nested promotes to parent)
- `selectionBefore` restored on undo, `selectionAfter` restored on redo
- Undo→redo = identity (ADR-009 invariant)
- Value-type copy independence (ADR-002)

## Risks / Trade-offs

- **[Unbounded log growth]** → Accepted for Milestone 1. Compaction is a future optimization (ADR-002). The `[UndoGroup]` + cursor structure accommodates future truncation.
- **[preconditionFailure on bad state]** → Deliberate. Defensive checks would mask bugs in recording logic. Crashes during development surface issues immediately.
- **[NSRange / UTF-16 coupling]** → Required at the Buffer boundary. Internal storage uses `NSRange` directly. When the rope arrives, the log's public API stays the same; only internal representation may change.

## Open Questions

- **Log compaction threshold:** Should there be a maximum number of undo groups (e.g., 200) after which oldest groups are silently dropped, or should this remain unbounded for v1? Decision deferred — no user-facing behavior change either way for typical session lengths. The `[UndoGroup] + cursor` structure already accommodates future truncation: drop oldest groups and optionally store a base snapshot representing the state before the earliest surviving group.
- **preconditionFailure diagnostic context:** If `OperationLog.undo(on:)` applies an inverse that the buffer rejects, the app crashes with `preconditionFailure`. This can only happen if the recording logic captured an operation inconsistently. While equivalence tests (TASK-006) guard against this, production crashes would be hard to diagnose. Consider adding a descriptive message to the `preconditionFailure` call that includes the operation kind and expected range.
