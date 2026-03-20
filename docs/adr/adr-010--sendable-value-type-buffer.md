---
status: accepted
date: 2026-03-20
title: "ADR-010: Sendable value-type buffer via protocol split"
---

# ADR-010: Sendable value-type buffer via protocol split

## Context

The app team needs to process ~50,000 in-memory notes concurrently (mass search-and-replace via `TaskGroup`). The building blocks exist — `TextRope` and `OperationLog` are both `Sendable` value types — but no single type combines them into a Sendable, undoable buffer.

The current `Buffer` protocol requires `AnyObject` (via `AsyncBuffer`), forcing all conformers to be classes. But `AnyObject` isn't functionally used anywhere — no identity checks (`===`), no existential boxing, no `ObjectIdentifier`. It was a conservative design choice.

`Mutex`-based isolation would work but requires macOS 15+; the deployment target is macOS 13.

## Decision

Extract a new base protocol `TextBuffer` (no `AnyObject`) that captures the sync read/write/selection surface with `mutating` mutation methods. `Buffer` refines it, keeping `AnyObject` via `AsyncBuffer`. A new Sendable struct `SendableRopeBuffer` conforms to `TextBuffer` and combines `TextRope` + `OperationLog` + selection.

Classes satisfy `mutating` requirements with non-mutating methods automatically, so existing `Buffer` conformers need no changes.

## Alternatives considered

- **Mutex-protected class:** Would require bumping the platform minimum from macOS 13 to macOS 15.
- **Standalone struct with parallel API:** No protocol sharing; duplicates the entire `Buffer` surface without code reuse.
- **Remove `AnyObject` from `Buffer` entirely:** Breaks the async bridging design in `AsyncBuffer` and the SIL workaround for the Swift compiler bug (see ADR notes in `AsyncBuffer.swift`).

## Consequences

- `SendableRopeBuffer` provides O(1) copy via COW (both `TextRope` and `OperationLog` are value types).
- Shared protocol surface (`TextBuffer`) with class-based buffers enables generic code that works with both.
- `OperationLog` replay works generically via new `popUndo()`/`popRedo()` methods that avoid exclusivity violations when the log is owned by the same struct being replayed on.
- Existing conformers (`MutableStringBuffer`, `RopeBuffer`, `NSTextViewBuffer`, `Undoable`, `TransferableUndoable`) are unaffected — they conform to `Buffer` which inherits `TextBuffer`.
