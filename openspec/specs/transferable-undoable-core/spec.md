## ADDED Requirements

### Requirement: Buffer conformance
`TransferableUndoable<Base>` SHALL conform to `Buffer` with `Range == NSRange` and `Content == String`. All read operations (`content`, `range`, `content(in:)`, `unsafeCharacter(at:)`) SHALL delegate to the wrapped base buffer. The `selectedRange` property SHALL delegate both get and set to the base buffer.

#### Scenario: Read-through to base buffer
- **WHEN** a `TransferableUndoable<MutableStringBuffer>` wraps a base buffer containing "Hello"
- **THEN** its `content` property SHALL return "Hello"
- **AND** its `range` property SHALL equal the base buffer's `range`
- **AND** `content(in:)` for valid ranges SHALL return the same substring as the base buffer

#### Scenario: Selected range delegates to base
- **WHEN** `selectedRange` is set to `NSRange(location: 2, length: 3)` on a `TransferableUndoable`
- **THEN** the base buffer's `selectedRange` SHALL equal `NSRange(location: 2, length: 3)`
- **AND** reading `selectedRange` back SHALL return `NSRange(location: 2, length: 3)`

### Requirement: Mutation recording with auto-grouping
Each mutation method (`insert(_:at:)`, `delete(in:)`, `replace(range:with:)`) SHALL auto-wrap the operation in an undo group when not already inside a `undoGrouping` block. The auto-group SHALL capture `selectionBefore` before the mutation and `selectionAfter` after. The mutation SHALL be delegated to the base buffer and recorded to the internal `OperationLog`.

#### Scenario: Insert records an undoable operation
- **WHEN** `insert("X", at: 0)` is called on a `TransferableUndoable` wrapping a buffer containing "abc"
- **THEN** the base buffer's content SHALL be "Xabc"
- **AND** `canUndo` SHALL return `true`

#### Scenario: Delete records an undoable operation
- **WHEN** `delete(in: NSRange(location: 0, length: 1))` is called on a buffer containing "abc"
- **THEN** the base buffer's content SHALL be "bc"
- **AND** `canUndo` SHALL return `true`

#### Scenario: Replace records an undoable operation
- **WHEN** `replace(range: NSRange(location: 0, length: 3), with: "XYZ")` is called on a buffer containing "abc"
- **THEN** the base buffer's content SHALL be "XYZ"
- **AND** `canUndo` SHALL return `true`

#### Scenario: Auto-grouping when not inside undoGrouping
- **WHEN** `insert("X", at: 0)` is called outside any `undoGrouping` block
- **THEN** the operation SHALL be wrapped in its own undo group automatically
- **AND** a single `undo()` call SHALL reverse the entire insert

#### Scenario: No auto-grouping inside undoGrouping
- **WHEN** `insert("A", at: 0)` and `insert("B", at: 1)` are called inside an `undoGrouping` block
- **THEN** both operations SHALL be part of the same undo group
- **AND** a single `undo()` call SHALL reverse both inserts

### Requirement: Nestable undo grouping
`undoGrouping(actionName:_:)` SHALL group all mutations performed within its block as a single undo step. Nested calls to `undoGrouping` SHALL merge operations into the outermost group. Only the outermost group closing SHALL commit to undo history.

#### Scenario: Single-level grouping
- **WHEN** two inserts are performed inside a single `undoGrouping` block
- **THEN** a single `undo()` call SHALL reverse both inserts
- **AND** `canUndo` SHALL be `false` after that single undo

#### Scenario: Nested grouping merges into parent
- **WHEN** an outer `undoGrouping` contains an inner `undoGrouping` with separate mutations in each
- **THEN** a single `undo()` call SHALL reverse all mutations from both the outer and inner group
- **AND** only one undo step SHALL exist in the history

#### Scenario: Action name propagation
- **WHEN** `undoGrouping(actionName: "Typing")` is used
- **THEN** the resulting undo group SHALL carry the action name "Typing"

### Requirement: Undo restores content and selection
`undo()` SHALL reverse the most recent undo group by applying inverse operations on the base buffer in reverse order. After undo, the buffer's content and `selectedRange` SHALL match the state captured as `selectionBefore` when the group was opened.

#### Scenario: Undo after insert
- **WHEN** "X" is inserted at position 0 into a buffer containing "abc" with selection at (0,0), then `undo()` is called
- **THEN** the content SHALL be "abc"
- **AND** `selectedRange` SHALL be restored to the selection before the insert

#### Scenario: Undo after delete
- **WHEN** the first character is deleted from "abc", then `undo()` is called
- **THEN** the content SHALL be "abc"
- **AND** `selectedRange` SHALL be restored to the selection before the delete

#### Scenario: Undo after grouped operations
- **WHEN** two inserts are grouped via `undoGrouping`, then `undo()` is called
- **THEN** both inserts SHALL be reversed
- **AND** `selectedRange` SHALL be restored to the selection before the group opened

#### Scenario: Undo when nothing to undo
- **WHEN** `undo()` is called and `canUndo` is `false`
- **THEN** the buffer content and selection SHALL remain unchanged

### Requirement: Redo restores content and selection
`redo()` SHALL reapply the most recently undone group by applying its operations in forward order. After redo, the buffer's content and `selectedRange` SHALL match the state captured as `selectionAfter` when the group was closed.

#### Scenario: Redo after undo
- **WHEN** "X" is inserted, then `undo()` is called, then `redo()` is called
- **THEN** the content SHALL contain the inserted "X"
- **AND** `selectedRange` SHALL match the selection after the original insert

#### Scenario: Undo then redo is identity
- **WHEN** a mutation is performed, then `undo()` then `redo()` are called
- **THEN** the buffer content and selection SHALL be identical to the state after the original mutation

#### Scenario: Redo tail truncation on new edit
- **WHEN** a mutation is performed, then `undo()` is called, then a new different mutation is performed
- **THEN** `canRedo` SHALL be `false`
- **AND** the previously undone operation SHALL no longer be redoable

#### Scenario: Redo when nothing to redo
- **WHEN** `redo()` is called and `canRedo` is `false`
- **THEN** the buffer content and selection SHALL remain unchanged

### Requirement: modifying method support
`modifying(affectedRange:_:)` SHALL auto-group if not already grouping, delegate to the base buffer, and record appropriate operations. The affected range content SHALL be captured before the block executes for undo purposes.

#### Scenario: modifying records an undoable operation
- **WHEN** `modifying(affectedRange:_:)` is called with a block that changes buffer content
- **THEN** `canUndo` SHALL be `true` after the call
- **AND** `undo()` SHALL restore the content that existed in the affected range before the block executed
