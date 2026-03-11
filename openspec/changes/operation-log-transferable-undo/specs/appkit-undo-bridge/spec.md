## ADDED Requirements

### Requirement: PuppetUndoManager delegates all state to the operation log

`PuppetUndoManager` SHALL subclass `NSUndoManager`. Its `undo()`, `redo()`, `canUndo`, `canRedo`, `undoActionName`, and `redoActionName` implementations SHALL delegate entirely to `TransferableUndoable` via the internal `PuppetUndoManagerDelegate` protocol. `PuppetUndoManager` SHALL store no undo state of its own. `groupsByEvent` SHALL be set to `false` in the initializer to prevent NSUndoManager's automatic grouping from interfering with the operation log's grouping stack.

#### Scenario: canUndo reflects log state
- **WHEN** `log.canUndo` is `false` (no committed undo groups)
- **THEN** `puppet.canUndo` is `false` and Edit > Undo is disabled in the menu

#### Scenario: canUndo becomes true after a mutation
- **WHEN** a mutation is recorded via `TransferableUndoable`, making `log.canUndo` true
- **THEN** `puppet.canUndo` is `true` without any additional synchronization step

#### Scenario: undoActionName reflects log action name
- **WHEN** an undo group with `actionName: "Typing"` is the most recent committed group
- **THEN** `puppet.undoActionName` is `"Typing"` and Edit > Undo shows "Undo Typing"

#### Scenario: redo state mirrors log
- **WHEN** `undo()` has been called making `log.canRedo` true with `redoActionName: "Typing"`
- **THEN** `puppet.canRedo` is `true` and `puppet.redoActionName` is `"Typing"`

---

### Requirement: PuppetUndoManager routes undo and redo to the operation log

Calling `puppet.undo()` SHALL invoke `TransferableUndoable.undo()`, which applies inverse operations via `OperationLog.undo(on:)` and restores `selectionBefore`. Calling `puppet.redo()` SHALL invoke `TransferableUndoable.redo()`, which reapplies operations via `OperationLog.redo(on:)` and restores `selectionAfter`. The base buffer SHALL reflect the updated content and selection after each call.

#### Scenario: Cmd+Z triggers operation log undo
- **WHEN** Cmd+Z is pressed in an `NSTextView` whose delegate returns the puppet from `undoManager(for:)`
- **THEN** `TransferableUndoable.undo()` is called exactly once, the buffer content is updated, and `selectedRange` is restored to `selectionBefore`

#### Scenario: Cmd+Shift+Z triggers operation log redo
- **WHEN** Cmd+Shift+Z is pressed after a previous undo
- **THEN** `TransferableUndoable.redo()` is called exactly once, the buffer content is updated, and `selectedRange` is restored to `selectionAfter`

#### Scenario: Undo when canUndo is false is a no-op
- **WHEN** `puppet.undo()` is called and `log.canUndo` is `false`
- **THEN** buffer content and selection are unchanged and no error is raised

---

### Requirement: PuppetUndoManager blocks external undo registration

`PuppetUndoManager` SHALL override all `registerUndo` variants as no-ops to prevent any external caller (including `NSTextView` itself) from registering undo actions on the puppet. This is defense-in-depth: `textView.allowsUndo = false` is the primary guard, and the no-op override is secondary.

#### Scenario: NSTextView does not pollute the puppet
- **WHEN** `textView.allowsUndo = false` is set and the puppet is installed as the text view's undo manager
- **THEN** typing in the text view does not cause any new undo groups to appear in the puppet's state beyond those recorded by `TransferableUndoable`

#### Scenario: Direct registerUndo call is silently ignored
- **WHEN** external code calls `puppet.registerUndo(withTarget: someObject, selector: #selector(…), object: nil)`
- **THEN** the call returns without error and the puppet's state is unchanged

---

### Requirement: Safe degradation when owner is deallocated

`PuppetUndoManager` SHALL hold a `weak` reference to its `PuppetUndoManagerDelegate` owner. If the owner is deallocated while the puppet is still installed as the text view's undo manager, all state queries SHALL return safe defaults (`canUndo: false`, `canRedo: false`, `undoActionName: ""`, `redoActionName: ""`), and calls to `undo()` or `redo()` SHALL be no-ops.

#### Scenario: Queries after owner deallocation return defaults
- **WHEN** the `TransferableUndoable` owner is deallocated and `puppet.canUndo` is queried
- **THEN** `puppet.canUndo` returns `false` without crashing

#### Scenario: undo() after owner deallocation is a no-op
- **WHEN** the owner is deallocated and `puppet.undo()` is called
- **THEN** no crash occurs and no buffer state is modified

---

### Requirement: enableSystemUndoIntegration() vends the puppet

`TransferableUndoable.enableSystemUndoIntegration()` SHALL create a `PuppetUndoManager` owned by the receiver, store it, and return it as `NSUndoManager`. Calling `enableSystemUndoIntegration()` more than once on the same `TransferableUndoable` SHALL return the same puppet instance. The puppet SHALL be wired to the receiver via `PuppetUndoManagerDelegate` immediately upon creation.

#### Scenario: Returned puppet is the installed undo manager
- **WHEN** `let puppet = transferable.enableSystemUndoIntegration()` is called and the puppet is installed via `NSTextViewDelegate.undoManager(for:)`
- **THEN** `puppet.canUndo` and `puppet.undoActionName` reflect `transferable`'s current log state without any further setup

#### Scenario: Repeated calls return the same instance
- **WHEN** `enableSystemUndoIntegration()` is called twice on the same `TransferableUndoable`
- **THEN** both calls return the same `NSUndoManager` instance (object identity)

---

### Requirement: App-side wiring contract

Consumers integrating `PuppetUndoManager` with an `NSTextView` SHALL:
1. Set `textView.allowsUndo = false` before the text view accepts any input.
2. Return the puppet from `NSTextViewDelegate.undoManager(for:)`.
3. Optionally return the same puppet from `NSWindowDelegate.windowWillReturnUndoManager(_:)` for window-level undo routing.

Failing to set `allowsUndo = false` MAY cause `NSTextView` to attempt registering its own undo actions; the puppet's no-op `registerUndo` override SHALL silently discard these, but content edits may appear un-undoable via the responder chain in degenerate configurations.

#### Scenario: Correct wiring enables Cmd+Z end-to-end
- **WHEN** `textView.allowsUndo = false`, the puppet is returned from `undoManager(for:)`, and a user types text
- **THEN** Cmd+Z undoes the typed text (restoring content and selection) and Edit > Undo is disabled after all history is exhausted

#### Scenario: Missing allowsUndo=false produces silent no-ops, not crashes
- **WHEN** `allowsUndo` is not set to `false` and `NSTextView` attempts to register undo actions
- **THEN** the puppet's `registerUndo` override discards the registration, the app does not crash, and `puppet.canUndo` reflects only operations recorded by `TransferableUndoable`
