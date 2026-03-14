---
status: accepted
date: 2026-03-11
title: "ADR-009: Undo and redo as proper inverses"
---

# ADR-009: Undo and redo as proper inverses

## Context

The operation log stores `selectionBefore` on each undo group. The question arose whether redo needs to explicitly restore selection state, or can rely on the buffer's automatic selection adjustment after replaying forward operations.

Buffer types adjust selection automatically after insert/delete/replace (shift right on insert before cursor, subtract on overlapping delete, etc.). In theory, replaying the forward operations should land the selection in the right place. In practice, this assumption is fragile — it depends on the exact sequence of selection adjustments being identical to the original execution, which may not hold for grouped operations with intermediate selection changes.

## Decision

Undo and redo are proper inverses. Both explicitly restore selection state:

- **Undo** restores `selectionBefore` — the selection as it was before the edit group executed.
- **Redo** restores `selectionAfter` — the selection as it was after the edit group executed.

`selectionAfter` is captured when the undo group closes (`endUndoGroup(selectionAfter:)`), not computed from replay.

The invariant: undo followed by redo (or redo followed by undo) produces zero observable difference in content or selection. They cancel out completely.

## Alternatives considered

**Redo without explicit selection restore.** Replay the forward operations and let the buffer's automatic selection adjustment determine the final cursor position. Simpler (no `selectionAfter` storage needed), but:
- The buffer's selection adjustment during replay may differ from the original because intermediate operations within a group may have moved the selection in ways that aren't captured by the final result
- Breaks the inverse invariant — undo→redo might leave the selection in a different position than before the undo
- Makes equivalence testing harder (can't assert exact state match after redo)

## Consequences

- **`UndoGroup` stores both `selectionBefore: NSRange` and `selectionAfter: NSRange?`.** Two `NSRange` values per group — trivial memory cost.
- **`selectionAfter` must be captured at group close, not group open.** `TransferableUndoable.undoGrouping` reads `base.selectedRange` after the block executes and passes it to `endUndoGroup(selectionAfter:)`. Single auto-grouped mutations capture it after the base mutation completes.
- **The inverse invariant is testable.** Every equivalence test can assert: perform operation, undo, redo → state identical to after the operation. Undo, redo, undo → state identical to before the operation. This is a mechanical property that can be checked exhaustively.
- **Selection during undo/redo replay is overwritten.** The buffer's automatic selection adjustments during `applyInverse`/`applyForward` still fire (they're part of `base.insert`/`base.delete`), but the final explicit `base.selectedRange = selectionBefore/After` overwrites whatever the automatic adjustments produced.
