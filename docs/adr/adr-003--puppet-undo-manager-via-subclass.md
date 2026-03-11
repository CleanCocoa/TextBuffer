---
status: accepted
date: 2026-03-11
title: "ADR-003: PuppetUndoManager via NSUndoManager subclass + allowsUndo=false"
---

# ADR-003: PuppetUndoManager via NSUndoManager subclass + allowsUndo=false

## Context

When `TransferableUndoable` replaces `NSUndoManager` as the undo engine, Cmd+Z and the Edit menu must still work. AppKit routes `undo:` actions through the responder chain and queries the undo manager for menu state (`canUndo`, `undoMenuItemTitle`). We need an `NSUndoManager` that AppKit can talk to, but whose undo/redo behavior is driven by our `OperationLog`.

Research confirmed:
- `NSTextView` has no private undo manager — it walks the responder chain to `NSWindow`
- `NSTextViewDelegate.undoManager(for:)` is an explicit hook Apple provides for custom undo managers
- `NSTextView.allowsUndo = false` prevents the text view from registering its own undo actions
- Cmd+Z flows: action up responder chain → `NSResponder.undo:` → `self.undoManager?.undo()`

## Decision

Subclass `NSUndoManager` as `PuppetUndoManager`. Override `undo()`, `redo()`, `canUndo`, `canRedo`, `undoActionName`, `redoActionName` to delegate to `TransferableUndoable` via an internal `PuppetUndoManagerDelegate` protocol. Override `registerUndo(withTarget:selector:object:)` as a no-op to prevent external pollution.

App-side wiring:
1. `textView.allowsUndo = false` — prevents NSTextView from registering its own actions
2. `NSTextViewDelegate.undoManager(for:)` returns the puppet
3. Optionally, `NSWindowDelegate.windowWillReturnUndoManager(_:)` returns the same puppet

The puppet maintains no internal state — it purely queries the operation log through its delegate.

## Alternatives considered

**Proxy action registration (push/sync pattern).** Register one proxy action on a standard `NSUndoManager` per undo group. When the proxy fires, delegate to the operation log. Requires maintaining the proxy stack in sync with the log — `pushToPuppet()` after each edit (O(1)), `syncPuppet()` after undo/redo/represent (O(k) rebuild). More complex, more state to manage, more ways to get out of sync.

**Swizzling NSTextView.** Replace the text view's undo: and redo: method implementations at runtime. Fragile, version-dependent, violates App Store guidelines.

**No bridge — manual menu management.** Disable the Edit menu items and provide custom UI for undo/redo. Breaks user expectations and accessibility.

## Consequences

- **Zero state in the puppet.** The puppet asks the log for everything. No synchronization needed after undo/redo/represent — the next query just reads current log state.
- **Edit menu works automatically.** `validateUserInterfaceItem:` reads `canUndo`/`undoMenuItemTitle` from the puppet, which reads from the log. "Undo Typing" / "Redo Paste" appear correctly. Edit > Undo grays out when the log is empty.
- **`allowsUndo = false` is load-bearing.** If the app forgets to set it, NSTextView registers its own undo actions. The no-op `registerUndo` override on the puppet is a defense-in-depth measure, but the app-side wiring must be documented clearly.
- **The puppet holds a weak reference to its owner** (TransferableUndoable). If the owner is deallocated, the puppet returns `false`/empty for all queries — safe degradation.
