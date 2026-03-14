## ADDED Requirements

### Requirement: Undo delegation
PuppetUndoManager SHALL delegate `undo()` to the owning TransferableUndoable's undo operation. When `undo()` is called on the puppet, the OperationLog's most recent group MUST be undone on the underlying buffer, restoring content and selection to their pre-edit state.

#### Scenario: Cmd+Z triggers OperationLog undo
- **WHEN** the user presses Cmd+Z and AppKit calls `undo()` on PuppetUndoManager
- **THEN** TransferableUndoable's `undo()` is invoked
- **AND** the buffer content and selection are restored to the state before the most recent undo group

#### Scenario: Multiple undos in sequence
- **WHEN** three edits have been made and `undo()` is called on the puppet three times
- **THEN** each call undoes one undo group in reverse chronological order
- **AND** the buffer content matches the state before each respective edit

### Requirement: Redo delegation
PuppetUndoManager SHALL delegate `redo()` to the owning TransferableUndoable's redo operation. When `redo()` is called on the puppet, the next redoable group MUST be reapplied on the underlying buffer, restoring content and selection to their post-edit state.

#### Scenario: Cmd+Shift+Z triggers OperationLog redo
- **WHEN** an edit has been undone and `redo()` is called on PuppetUndoManager
- **THEN** TransferableUndoable's `redo()` is invoked
- **AND** the buffer content and selection are restored to the state after the undone edit

### Requirement: canUndo reflects log state
PuppetUndoManager's `canUndo` property SHALL return `true` if and only if the OperationLog contains at least one undoable group.

#### Scenario: canUndo is false on empty log
- **WHEN** no edits have been made
- **THEN** `puppet.canUndo` returns `false`

#### Scenario: canUndo is true after an edit
- **WHEN** an edit has been recorded in the OperationLog
- **THEN** `puppet.canUndo` returns `true`

#### Scenario: canUndo is false after undoing all edits
- **WHEN** all edits have been undone
- **THEN** `puppet.canUndo` returns `false`

### Requirement: canRedo reflects log state
PuppetUndoManager's `canRedo` property SHALL return `true` if and only if the OperationLog contains at least one redoable group.

#### Scenario: canRedo is false when no undo has occurred
- **WHEN** edits have been made but none have been undone
- **THEN** `puppet.canRedo` returns `false`

#### Scenario: canRedo is true after an undo
- **WHEN** an edit has been undone
- **THEN** `puppet.canRedo` returns `true`

#### Scenario: canRedo is false after a new edit following undo
- **WHEN** an edit is undone and then a new edit is made (truncating the redo tail)
- **THEN** `puppet.canRedo` returns `false`

### Requirement: Undo action name reflects log state
PuppetUndoManager's `undoActionName` property SHALL return the action name of the most recent undoable group from the OperationLog, or an empty string if no undoable group exists.

#### Scenario: undoActionName shows current action
- **WHEN** an edit group is recorded with actionName "Typing"
- **THEN** `puppet.undoActionName` returns `"Typing"`

#### Scenario: undoActionName is empty when log is empty
- **WHEN** no edits have been made
- **THEN** `puppet.undoActionName` returns `""`

#### Scenario: Edit menu displays correct undo title
- **WHEN** AppKit queries `undoMenuItemTitle` for the Edit menu
- **THEN** the menu item reads "Undo Typing" (or the appropriate action name)

### Requirement: Redo action name reflects log state
PuppetUndoManager's `redoActionName` property SHALL return the action name of the next redoable group from the OperationLog, or an empty string if no redoable group exists.

#### Scenario: redoActionName shows undone action
- **WHEN** an edit group with actionName "Typing" has been undone
- **THEN** `puppet.redoActionName` returns `"Typing"`

#### Scenario: redoActionName is empty when no redo available
- **WHEN** no edits have been undone
- **THEN** `puppet.redoActionName` returns `""`

### Requirement: External undo registration blocked
PuppetUndoManager MUST override all NSUndoManager registration entry points as no-ops. Direct calls to `registerUndo(withTarget:selector:object:)`, `registerUndo(withTarget:handler:)`, and `prepare(withInvocationTarget:)` on the puppet SHALL have no effect on undo/redo state.

#### Scenario: registerUndo with selector is ignored
- **WHEN** external code calls `registerUndo(withTarget:selector:object:)` on the puppet
- **THEN** no undo action is registered
- **AND** `canUndo` remains unchanged

#### Scenario: registerUndo with handler is ignored
- **WHEN** external code calls `registerUndo(withTarget:handler:)` on the puppet
- **THEN** no undo action is registered
- **AND** `canUndo` remains unchanged

#### Scenario: prepare(withInvocationTarget:) is neutralized
- **WHEN** external code calls `prepare(withInvocationTarget:)` on the puppet
- **THEN** no undo action is registered regardless of subsequent method calls

### Requirement: Safe degradation on owner deallocation
PuppetUndoManager SHALL hold a weak reference to its owning TransferableUndoable. If the owner is deallocated, all property queries MUST return safe defaults: `false` for `canUndo`/`canRedo`, empty string for action names. Calls to `undo()`/`redo()` MUST be no-ops.

#### Scenario: Queries after owner deallocation
- **WHEN** the owning TransferableUndoable is deallocated
- **THEN** `puppet.canUndo` returns `false`
- **AND** `puppet.canRedo` returns `false`
- **AND** `puppet.undoActionName` returns `""`
- **AND** `puppet.redoActionName` returns `""`

#### Scenario: Undo/redo after owner deallocation
- **WHEN** the owning TransferableUndoable is deallocated and `undo()` is called
- **THEN** no crash occurs and no state changes

### Requirement: enableSystemUndoIntegration idempotence
Calling `enableSystemUndoIntegration()` on a TransferableUndoable MUST return the same PuppetUndoManager instance on every call. The returned type SHALL be `NSUndoManager`.

#### Scenario: Repeated calls return same instance
- **WHEN** `enableSystemUndoIntegration()` is called twice on the same TransferableUndoable
- **THEN** both calls return the identical object (same reference)

#### Scenario: Return type is NSUndoManager
- **WHEN** `enableSystemUndoIntegration()` is called
- **THEN** the return value is typed as `NSUndoManager`
- **AND** the underlying instance is a PuppetUndoManager

### Requirement: groupsByEvent disabled
PuppetUndoManager MUST set `groupsByEvent` to `false` during initialization to prevent AppKit's automatic run-loop-based grouping from interfering with OperationLog's grouping.

#### Scenario: Automatic grouping is disabled
- **WHEN** a PuppetUndoManager is created
- **THEN** `puppet.groupsByEvent` is `false`

### Requirement: AppKit integration with NSTextView
When wired correctly (`textView.allowsUndo = false`, delegate returns puppet via `undoManager(for:)`), Cmd+Z and Cmd+Shift+Z in an NSTextView MUST trigger OperationLog undo/redo through the puppet. The Edit menu MUST reflect the correct enabled state and action names.

#### Scenario: Cmd+Z in NSTextView triggers log undo
- **WHEN** an NSTextView is configured with `allowsUndo = false` and its delegate returns PuppetUndoManager
- **AND** the user presses Cmd+Z
- **THEN** the OperationLog's most recent group is undone on the buffer

#### Scenario: Edit menu grays out Undo when log is empty
- **WHEN** the OperationLog has no undoable groups
- **THEN** the Edit > Undo menu item is disabled (grayed out)

#### Scenario: NSTextView with allowsUndo=false does not register its own actions
- **WHEN** `textView.allowsUndo` is set to `false` and text is edited through the buffer
- **THEN** NSTextView does not call `registerUndo` on the puppet
- **AND** only OperationLog-recorded groups appear as undo steps
