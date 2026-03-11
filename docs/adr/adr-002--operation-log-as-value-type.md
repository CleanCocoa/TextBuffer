---
status: accepted
date: 2026-03-11
title: "ADR-002: OperationLog as a value type for buffer transfer"
---

# ADR-002: OperationLog as a value type for buffer transfer

## Context

An app has one `NSTextView` editor and many in-memory buffers. When the user switches documents, content + selection + undo history must transfer between the editor and in-memory copies. The transferred copies must be independent — undoing on one must not affect the other.

Five alternative approaches were researched. NSUndoManager-based approaches all fail because undo closures capture typed references to specific `Undoable<Base>` instances and cannot be retargeted, copied, or extracted. Snapshot-based (memento) approaches work but are memory-heavy: 50 snapshots of a 1MB document = 50MB.

## Decision

Record mutations as value-type `BufferOperation` values inside an `OperationLog` struct. The log is a plain Swift value type — `let copy = log` produces an independent copy with zero shared mutable state. Buffer transfer = copy the log.

The log maintains:
- A **history** array of completed `UndoGroup`s with a cursor for undo/redo
- A **grouping stack** for nested recording (beginUndoGroup/endUndoGroup)

Undo applies inverse operations in reverse; redo reapplies forward. Both are generic over `Buffer` — the same log can drive undo on any buffer type.

## Alternatives considered

**Snapshot-based (memento).** Store full content copies at each undo point. Viable but memory-heavy and forces full NSTextView relayout on undo (entire content replacement). The operation log applies surgical deltas instead.

**Proxy/trampoline.** A stable intermediary holding a settable buffer reference, so closures always target the proxy. Fails because closures are typed to `Undoable<T>` (not type-erased), retargeting makes ALL closures operate on the new buffer, and `Undoable.deinit` destroys actions.

**Buffer-agnostic UndoHistory.** Nearly identical to the operation log but with unnecessary indirection layers. Over-engineered for current needs.

**Persistent data structures (rope versions).** The right long-term answer — snapshot = copy root pointer, O(1). But requires the rope to exist first. The operation log is the interim solution; when the rope arrives, the log's internal representation can switch from `[BufferOperation]` to version pointers while the public API stays the same.

## Consequences

- **O(1) buffer transfer.** `snapshot()` copies the log (value-type copy = memcpy of the array). Content is copied separately via `MutableStringBuffer(wrapping:)`.
- **O(k) undo** where k = operations in the group. Each operation is replayed as an inverse. Acceptable for typical edit groups (1–20 operations).
- **Unbounded growth.** Long editing sessions grow the log without limit. Compaction (base snapshot + recent deltas) is a future optimization. The log's internal structure (`[UndoGroup]` + cursor) accommodates this — truncate oldest groups and optionally store a base snapshot.
- **The public API (`snapshot`, `represent`, `undoGrouping`) is stable.** When the rope subsumes the log's content history, only `OperationLog`'s internals change. Selection state (`selectionBefore`/`selectionAfter` per group) still needs separate tracking regardless of backing store.
