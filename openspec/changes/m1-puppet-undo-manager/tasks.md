## 1. PuppetUndoManagerDelegate Protocol

- [ ] 1.1 Define `PuppetUndoManagerDelegate` internal protocol in `Sources/TextBuffer/Buffer/PuppetUndoManager.swift` with six delegate methods: `puppetUndo()`, `puppetRedo()`, `puppetCanUndo: Bool`, `puppetCanRedo: Bool`, `puppetUndoActionName: String`, `puppetRedoActionName: String`. Protocol must be `@MainActor` and `AnyObject`-constrained.

## 2. PuppetUndoManager Subclass

- [ ] 2.1 Implement `PuppetUndoManager` as `@MainActor public final class` inheriting `NSUndoManager` in `Sources/TextBuffer/Buffer/PuppetUndoManager.swift`. Store `weak var owner: (any PuppetUndoManagerDelegate)?`. Set `groupsByEvent = false` in `init`.
- [ ] 2.2 Override `undo()` and `redo()` to delegate to `owner?.puppetUndo()` and `owner?.puppetRedo()` respectively.
- [ ] 2.3 Override `canUndo` and `canRedo` computed properties to return `owner?.puppetCanUndo ?? false` and `owner?.puppetCanRedo ?? false`.
- [ ] 2.4 Override `undoActionName` and `redoActionName` to return `owner?.puppetUndoActionName ?? ""` and `owner?.puppetRedoActionName ?? ""`.
- [ ] 2.5 Override all three registration entry points as no-ops: `registerUndo(withTarget:selector:object:)`, `registerUndo(withTarget:handler:)`, and `prepare(withInvocationTarget:)` (return `self`).

## 3. TransferableUndoable Integration

- [ ] 3.1 Add `private var puppetUndoManager: PuppetUndoManager?` stored property to `TransferableUndoable`.
- [ ] 3.2 Conform `TransferableUndoable` to `PuppetUndoManagerDelegate` in an extension, delegating to `log.canUndo`, `log.canRedo`, `log.undoActionName`, `log.redoActionName`, `undo()`, and `redo()`.
- [ ] 3.3 Implement `enableSystemUndoIntegration() -> NSUndoManager` on `TransferableUndoable`: lazily create and cache a `PuppetUndoManager(owner: self)`, return the same instance on repeated calls. Guard with `#if canImport(AppKit)`.

## 4. Unit Tests

- [ ] 4.1 Create `Tests/TextBufferTests/PuppetUndoManagerTests.swift`. Test that `puppet.canUndo`/`canRedo` reflect log state: false on empty, true after edit, false after undoing all, true for canRedo after undo, false for canRedo after new edit.
- [ ] 4.2 Test that `puppet.undo()` triggers log undo (content and selection restored) and `puppet.redo()` triggers log redo.
- [ ] 4.3 Test that `puppet.undoActionName`/`redoActionName` reflect log action names, including empty string when no groups exist.
- [ ] 4.4 Test that direct `registerUndo(withTarget:selector:object:)` and `registerUndo(withTarget:handler:)` calls on the puppet do not change `canUndo`.
- [ ] 4.5 Test that `puppet.groupsByEvent` is `false`.
- [ ] 4.6 Test that `enableSystemUndoIntegration()` returns the same instance on repeated calls (identity check with `===`).
- [ ] 4.7 Test safe degradation after owner deallocation: create puppet, nil out the TransferableUndoable, verify `canUndo == false`, `canRedo == false`, `undoActionName == ""`, `redoActionName == ""`, and `undo()`/`redo()` do not crash.

## 5. Integration Test

- [ ] 5.1 Write an integration test that creates an NSTextView in a window, configures `allowsUndo = false`, returns PuppetUndoManager from `undoManager(for:)`, performs edits via TransferableUndoable, and verifies that Cmd+Z (simulated via `puppet.undo()`) correctly undoes the edit. Verify Edit menu state via `puppet.canUndo` and `puppet.undoActionName`.
