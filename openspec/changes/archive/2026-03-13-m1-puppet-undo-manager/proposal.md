## Why

TransferableUndoable replaces NSUndoManager as the undo engine, but AppKit still routes Cmd+Z and Edit menu state through the responder chain's `undoManager` property. Without a bridging NSUndoManager subclass, there is no way for the operation-log-based undo to participate in standard macOS keyboard shortcuts and menu validation. This is TASK-007 on the Milestone 1 critical path (Phase 4: AppKit Bridge), and it must land before the Transfer API integration tests (TASK-009) can exercise the full stack.

## What Changes

- New `PuppetUndoManager` class — an `NSUndoManager` subclass that delegates `undo()`, `redo()`, `canUndo`, `canRedo`, `undoActionName`, `redoActionName` to `TransferableUndoable` via an internal `PuppetUndoManagerDelegate` protocol. Overrides `registerUndo` variants as no-ops to block external pollution.
- New `PuppetUndoManagerDelegate` internal protocol defining the six delegate hooks.
- New `enableSystemUndoIntegration()` method on `TransferableUndoable` that lazily creates and caches a `PuppetUndoManager`, returning it as `NSUndoManager`.
- `TransferableUndoable` gains conformance to `PuppetUndoManagerDelegate`.

## Capabilities

### New Capabilities
- `puppet-undo-manager`: PuppetUndoManager behavior — delegates undo/redo/canUndo/canRedo/actionNames to TransferableUndoable's OperationLog, blocks external undo registration, integrates with Cmd+Z and Edit menu via AppKit's responder chain

### Modified Capabilities

(none)

## Impact

- **New file:** `Sources/TextBuffer/Buffer/PuppetUndoManager.swift` — PuppetUndoManager class + PuppetUndoManagerDelegate protocol
- **Modified file:** `Sources/TextBuffer/Buffer/TransferableUndoable.swift` — adds `enableSystemUndoIntegration()`, PuppetUndoManagerDelegate conformance, `puppetUndoManager` stored property
- **New file:** `Tests/TextBufferTests/PuppetUndoManagerTests.swift` — unit and integration tests
- **API surface:** One new public method (`enableSystemUndoIntegration() -> NSUndoManager`), one new public class (`PuppetUndoManager`), one new internal protocol
- **Dependencies:** Requires TASK-005 (TransferableUndoable core) to be complete
- **ADR:** ADR-003 documents the design rationale (subclass approach, allowsUndo=false, weak owner reference)
