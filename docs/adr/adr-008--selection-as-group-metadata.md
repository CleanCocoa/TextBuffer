---
status: accepted
date: 2026-03-11
title: "ADR-008: Selection is group metadata, not an undo step"
---

# ADR-008: Selection is group metadata, not an undo step

## Context

The existing `Undoable<Base>` has an `isRestoringSelection` flag that optionally tracks cursor movements as undoable actions. The operation log needs to decide how selection state interacts with undo/redo.

Two models:
1. Selection changes are independent undo steps — moving the cursor then undoing restores the previous cursor position
2. Selection is metadata attached to edit groups — stored as "where was the cursor before/after this edit," not as an operation itself

## Decision

Selection is metadata on undo groups, not a standalone operation. Each `UndoGroup` stores `selectionBefore` (captured when the group opens) and `selectionAfter` (captured when the group closes). Undo restores `selectionBefore`; redo restores `selectionAfter`. Moving the cursor without editing is not recorded and not undoable.

## Alternatives considered

**Selection as undoable operation.** Track every `select()` / `selectedRange = ...` call as a `BufferOperation.select(range:)` in the log. This allows undoing pure cursor movement. Some editors (notably Emacs with its mark ring) support this. However:
- It does not match NSTextView's default behavior — Apple's undo never restores cursor position without a content change
- It pollutes the undo stack with noise — users pressing arrow keys would generate dozens of undo steps
- It complicates the operation log (selection "operations" have no inverse content change)

## Consequences

- **Undo/redo are proper inverses.** Undo restores the exact `selectionBefore` state. Redo restores the exact `selectionAfter` state. Undo then redo (or vice versa) produces zero observable difference — content and selection are identical to before. This is the mathematical invariant that drives correctness testing.
- **Cursor movement is invisible to the undo system.** If a user moves the cursor, then undoes, the cursor jumps to `selectionBefore` of the last edit group — not to where it was before the cursor movement. This matches standard text editor behavior.
- **`selectionAfter` must be captured at group close, not group open.** The final selection after all operations in a group have executed is the state that redo should restore. `TransferableUndoable.undoGrouping` captures `base.selectedRange` after the block executes and passes it to `endUndoGroup(selectionAfter:)`.
