---
status: accepted
date: 2026-03-11
title: "ADR-001: Dual undo implementations — TransferableUndoable alongside Undoable"
---

# ADR-001: Dual undo implementations — TransferableUndoable alongside Undoable

## Context

TextBuffer needs a new undo system (`OperationLog`) to enable buffer transfer — copying undo history between buffer types. The existing `Undoable<Base>` uses `NSUndoManager` internally, which cannot transfer undo stacks (closures capture typed references to specific instances, `deinit` destroys actions, no Foundation API exists to copy or retarget actions).

The question: do we replace `Undoable`'s internals with the operation log, or introduce a new type?

## Decision

Introduce `TransferableUndoable<Base>` as a new type alongside the existing `Undoable<Base>`. The existing `Undoable` is not modified.

## Alternatives considered

**Replace Undoable internals.** Swap `NSUndoManager` for `OperationLog` inside the existing `Undoable<Base>`. Simpler API surface (one type), but destroys the behavioral oracle. The `NSUndoManager`-backed implementation is the only proven-correct reference for undo/redo edge cases. Once it's gone, there's nothing to test the operation log against.

**Deprecate Undoable immediately.** Ship `TransferableUndoable` as the only option. Premature — the new implementation is unproven and AppKit integration (PuppetUndoManager) adds risk.

## Consequences

- **Drift testing becomes possible.** `Undoable<MutableStringBuffer>` serves as the gold standard: run identical operation sequences on both implementations, assert identical content + selection after every step. This is the primary correctness mechanism for the operation log.
- **Two types to maintain.** The API surface is larger. Consumers must choose between `Undoable` (simple, NSUndoManager-backed, no transfer) and `TransferableUndoable` (operation-log-backed, supports transfer).
- **Future deprecation path.** Once `TransferableUndoable` is proven correct via extensive equivalence testing, `Undoable` can be deprecated in a future major version. The equivalence tests themselves become regression tests at that point.
- **No breaking change.** Existing consumers of `Undoable` are unaffected.
