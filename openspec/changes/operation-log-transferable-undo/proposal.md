## Why

The existing `Undoable<Base>` is backed by `NSUndoManager`, whose undo closures capture typed references to specific buffer instances — making it impossible to copy, retarget, or transfer undo history between buffer types. An app with one `NSTextView` editor and many in-memory documents needs to switch documents while preserving each document's complete undo stack. That transfer is currently impossible without losing history.

## What Changes

- Introduce `OperationLog` — a value-type undo/redo stack that records reversible `BufferOperation` deltas in nested `UndoGroup`s. Because it is a plain Swift value type, buffer transfer reduces to a value copy.
- Introduce `TransferableUndoable<Base>` — a new `Buffer`-conforming decorator backed by `OperationLog`. It records every mutation, provides nestable `undoGrouping`, and exposes `undo()`/`redo()` that restore both content and selection.
- Add `snapshot()` and `represent(_:)` to `TransferableUndoable` for full-state buffer transfer (content + selection + undo history).
- Introduce `PuppetUndoManager` — an `NSUndoManager` subclass that delegates all undo/redo/menu-state queries to the operation log via `TransferableUndoable`, enabling Cmd+Z and the Edit menu without AppKit managing any undo state itself.
- Add `BufferStep` enum and `assertUndoEquivalence` to `TextBufferTesting` to enable behavioral drift testing against the existing `Undoable<Base>` gold standard.
- The existing `Undoable<Base>` is **not modified**. It continues to serve as the correctness oracle for equivalence testing.

## Capabilities

### New Capabilities

- `buffer-transfer-undo`: The full behavior contract for `OperationLog`, `TransferableUndoable`, and the `snapshot()`/`represent()` transfer API — how operations are recorded, grouped, undone, redone, and transferred between buffer instances.
- `appkit-undo-bridge`: The behavior contract for `PuppetUndoManager` — how it bridges `TransferableUndoable`'s operation log to AppKit's Cmd+Z responder chain and Edit menu state, and what app-side wiring is required.

### Modified Capabilities

(none — no existing specs change requirements)

## Impact

- **New source files:** `BufferOperation.swift`, `UndoGroup.swift`, `OperationLog.swift`, `TransferableUndoable.swift`, `PuppetUndoManager.swift` in `Sources/TextBuffer`; `BufferStep.swift`, `AssertUndoEquivalence.swift` in `Sources/TextBufferTesting`.
- **New test files:** `OperationLogTests.swift`, `TransferableUndoableTests.swift`, `UndoEquivalenceDriftTests.swift`, `PuppetUndoManagerTests.swift`, `TransferAPITests.swift`, `TransferIntegrationTests.swift` in `Tests/TextBufferTests`.
- **No breaking changes.** All new types. Existing `Undoable<Base>`, `MutableStringBuffer`, and `NSTextViewBuffer` are unchanged.
- **Scoped to TASK-001 through TASK-009** (Milestone 1: Operation Log). Milestone 2 (Rope) and the convergence task (TASK-021) are out of scope.
