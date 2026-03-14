## Why

TASK-005 and TASK-006 from the Milestone 1 roadmap deliver the core undo decorator that makes buffer transfer possible. `TransferableUndoable<Base>` wraps any `Buffer` with `OperationLog`-backed undo/redo, replacing the non-transferable `NSUndoManager` closure model. Without this type, `snapshot()` and `represent(_:)` — the transfer primitives — have nothing to attach to. Equivalence drift tests (TASK-006) then prove correctness by running identical edit sequences on both `Undoable` (gold standard) and `TransferableUndoable` (subject), per ADR-001's dual-implementation strategy.

## What Changes

- **New decorator**: `TransferableUndoable<Base: Buffer>` — full `Buffer` conformance with mutation recording, auto-grouping, nestable `undoGrouping`, and `undo()`/`redo()` with selection restoration. Does NOT include `PuppetUndoManager` bridge or transfer API (`snapshot`/`represent`) — those are TASK-007 and TASK-008 respectively.
- **New testing harness**: `assertUndoEquivalence` function and `BufferStep` enum in `TextBufferTesting`, enabling step-by-step behavioral comparison between `Undoable` and `TransferableUndoable`.
- **New drift test suite**: `UndoEquivalenceDriftTests` exercising insert, delete, replace, grouped operations, interleaved edits and undos, redo tail truncation, and selection state at every step.

## Capabilities

### New Capabilities

- `transferable-undoable-core`: `TransferableUndoable<Base>` Buffer conformance, mutation recording with auto-grouping, nestable `undoGrouping`, undo/redo with selection restoration
- `undo-equivalence-testing`: Behavioral drift testing proving `TransferableUndoable` ≡ `Undoable` for all edit/undo/redo scenarios

### Modified Capabilities

_(none — no existing spec requirements change)_

## Impact

- **New source files**: `Sources/TextBuffer/Buffer/TransferableUndoable.swift`
- **New test helpers**: `Sources/TextBufferTesting/AssertUndoEquivalence.swift`
- **New test files**: `Tests/TextBufferTests/TransferableUndoableTests.swift`, `Tests/TextBufferTests/UndoEquivalenceDriftTests.swift`
- **Dependencies**: Requires `OperationLog` (TASK-004) to be implemented. `BufferStep` and `assertUndoEquivalence` depend on both `Undoable` (existing) and `TransferableUndoable` (this change).
- **API surface**: Adds `TransferableUndoable` to the `TextBuffer` module public API; adds `BufferStep` and `assertUndoEquivalence` to `TextBufferTesting` public API.
