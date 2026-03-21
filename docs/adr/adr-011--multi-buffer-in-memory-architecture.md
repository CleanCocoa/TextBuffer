---
status: accepted
date: 2026-03-21
title: "ADR-011: Multi-buffer in-memory architecture"
---

# ADR-011: Multi-buffer in-memory architecture

## Context

A text editor or note-taking application needs to hold thousands of documents in memory simultaneously. Not all are displayed — some are open but off-screen, some are visited programmatically (search-and-replace, tag extraction, indexing), and only one or a few are rendered in a text view at any time. The system must support:

- **Thousands of buffers in memory**, each with content, selection, and undo history.
- **Concurrent programmatic mutation** across many buffers (batch find-and-replace via `TaskGroup`).
- **Display switching** — promoting an in-memory buffer to a visible text view, or demoting a visible buffer back to in-memory.
- **Background processing** — visiting buffers for read-only analysis (word counts, tag extraction, search indexing) without blocking the UI.
- **Undo integrity** — each buffer's undo history survives transfers between isolation domains and display state changes.

## Decision

The TextBuffer library provides a tiered architecture where buffer types map to lifecycle phases:

### Tier 1: Cold storage — `SendableRopeBuffer` (Sendable struct)

Thousands of these exist simultaneously. Each is a self-contained value type (`TextRope` + `OperationLog` + selection) with O(1) COW copy. They live outside `@MainActor` isolation, enabling:

- Concurrent batch processing in `TaskGroup` (tested at 1000 parallel buffers).
- Background analysis via `TextAnalysisCapable` conformance (`wordRange`, `lineRange`).
- Cross-isolation transfer without coordination.
- Undo/redo replay via `popUndo()`/`popRedo()` without exclusivity violations.

### Tier 2: Active editing — `TransferableUndoable<RopeBuffer>` (@MainActor)

The currently-displayed buffer is wrapped in `TransferableUndoable` for UI integration. This provides:

- `PuppetUndoManager` bridge for system Edit menu integration.
- Auto-grouping of mutations into undo steps.
- `@MainActor` isolation matching AppKit/UIKit requirements.

### Tier transitions

Buffers move between tiers via snapshot/represent:

| Transition | Method | Cost |
|-----------|--------|------|
| Cold → Active | `sendableRopeBuffer.toTransferableUndoable()` | O(n) content copy + log transfer |
| Active → Cold | `transferableUndoable.sendableSnapshot()` | O(1) when base is `RopeBuffer` (rope COW) |
| Cold → Cold (mutate) | Value-type mutation on `SendableRopeBuffer` | O(1) COW per mutation |
| Active ← Cold (sync back) | `transferableUndoable.represent(snapshot)` | O(n) content replace + log overwrite |

### Protocol surface

Generic code uses `TextBuffer` (not `Buffer`) as the constraint for operations that work across all tiers:

- `assertBufferState`, `MutableStringBuffer.init(copying:)`, `RopeBuffer.init(copying:)` accept `TextBuffer`.
- `TextAnalysisCapable: TextBuffer` enables word/line analysis on both struct and class buffers.
- `SendableRopeBuffer.comparator(.content, .selection)` provides configurable equality for collection operations.

## Alternatives considered

- **All buffers as classes with Mutex:** Would work on macOS 15+ but requires platform bump from macOS 13. Mutex contention at 50k scale is a concern.
- **Actor-per-buffer:** Each buffer as an actor provides isolation but adds overhead for cross-actor calls. Batch processing requires `await` for every mutation, defeating `TaskGroup` parallelism.
- **Single shared buffer pool:** A centralized actor managing all buffers. Serializes all access, becoming a bottleneck at scale. Violates the principle that independent buffers should be independently mutable.

## Consequences

### What works today

- 1000+ concurrent buffer mutations in `TaskGroup` (tested, COW-verified).
- Round-trip `sendableSnapshot()` → mutate → `represent()` preserves undo history.
- Display switching: promote cold buffer to `TransferableUndoable` for editing, demote back to `SendableRopeBuffer` for storage.
- Word/line range analysis on all buffer types via `TextAnalysisCapable`.
- Undo equivalence testing via `assertSendableUndoEquivalence` drift tests.

### Known limitations for future work

- **OperationLog grows unbounded.** Each buffer's `[UndoGroup]` array has no compaction or depth limit. At 50k buffers with editing history, memory grows proportionally. Future: base-snapshot + recent-deltas compaction (see ADR-002).
- **No cross-buffer undo.** Each buffer has an independent log. "Undo batch find-and-replace across 100 notes" requires application-level coordination above the buffer layer.
- **`represent()` is O(n).** Writing a snapshot back to a displayed buffer replaces the entire content string. Future: rope-level diff-and-patch for incremental updates.
- **No eviction policy.** All buffers are retained equally. Future: LRU eviction of undo history for cold buffers, or tiered storage (content-only vs content+undo).

### Scaling path

1. **Current (0.5.0):** Foundation — `SendableRopeBuffer` + protocol split + conversion surface. Validated at 1000 concurrent buffers.
2. **Next:** OperationLog compaction — base snapshots with recent deltas. Bounds memory per buffer.
3. **Later:** Shared undo coordinator for cross-buffer batch operations. Memory budgeting with LRU eviction of cold undo history.
