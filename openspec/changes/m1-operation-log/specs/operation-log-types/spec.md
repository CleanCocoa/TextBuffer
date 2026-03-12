## ADDED Requirements

### Requirement: BufferOperation value type
`BufferOperation` SHALL be a public struct conforming to `Sendable` and `Equatable`. It SHALL contain a single stored property `kind` of type `BufferOperation.Kind`.

`BufferOperation.Kind` SHALL be a public enum conforming to `Sendable` and `Equatable` with exactly three cases:
- `insert(content: String, at: Int)` — text was inserted at a UTF-16 offset
- `delete(range: NSRange, deletedContent: String)` — text was deleted from a range
- `replace(range: NSRange, oldContent: String, newContent: String)` — text in a range was replaced

#### Scenario: BufferOperation is Equatable
- **WHEN** two `BufferOperation` values are created with identical `kind` values
- **THEN** they SHALL compare as equal via `==`

#### Scenario: BufferOperation is a value type
- **WHEN** a `BufferOperation` is assigned to a new variable and the original is mutated
- **THEN** the copy SHALL remain unchanged

#### Scenario: Different operation kinds are not equal
- **WHEN** an `insert` operation and a `delete` operation are compared
- **THEN** they SHALL compare as not equal

---

### Requirement: UndoGroup value type
`UndoGroup` SHALL be a public struct conforming to `Sendable` and `Equatable`. It SHALL contain:
- `operations: [BufferOperation]` — the operations in execution order
- `selectionBefore: NSRange` — selection state before the group executed
- `selectionAfter: NSRange?` — selection state after the group executed (nil until group closes)
- `actionName: String?` — optional user-facing name for the Edit menu

#### Scenario: UndoGroup stores operations in order
- **WHEN** an `UndoGroup` is created with operations [A, B, C]
- **THEN** `operations` SHALL return [A, B, C] in that order

#### Scenario: UndoGroup is Equatable
- **WHEN** two `UndoGroup` values have identical operations, selectionBefore, selectionAfter, and actionName
- **THEN** they SHALL compare as equal

#### Scenario: UndoGroup stores selection metadata
- **WHEN** an `UndoGroup` is created with `selectionBefore: NSRange(location: 0, length: 5)`
- **THEN** `selectionBefore` SHALL return `NSRange(location: 0, length: 5)`

---

### Requirement: OperationLog initialization
`OperationLog` SHALL be a public struct conforming to `Sendable` and `Equatable`. A freshly initialized `OperationLog` SHALL have an empty history, cursor at zero, and an empty grouping stack.

#### Scenario: Fresh log has no undo or redo
- **WHEN** an `OperationLog` is initialized via `OperationLog()`
- **THEN** `canUndo` SHALL be `false` and `canRedo` SHALL be `false` and `undoableCount` SHALL be `0`

#### Scenario: Fresh log is not grouping
- **WHEN** an `OperationLog` is initialized
- **THEN** `isGrouping` SHALL be `false`

---

### Requirement: Recording operations into groups
`OperationLog.record(_:)` SHALL append a `BufferOperation` to the topmost open group on the grouping stack. Calling `record(_:)` when no group is open SHALL trigger a `preconditionFailure`.

#### Scenario: Record into an open group
- **WHEN** `beginUndoGroup` is called, then `record` is called with an insert operation
- **THEN** the operation SHALL be appended to the current open group

#### Scenario: Record outside a group fails
- **WHEN** `record(_:)` is called on a log with no open group
- **THEN** a `preconditionFailure` SHALL occur

---

### Requirement: Begin and end undo grouping
`beginUndoGroup(selectionBefore:actionName:)` SHALL push a new `UndoGroup` onto the grouping stack with the given `selectionBefore` and optional `actionName`. `endUndoGroup(selectionAfter:)` SHALL pop the top group from the stack and set its `selectionAfter`.

When the stack becomes empty after popping (top-level close), the completed group SHALL be committed to the history at the cursor position and the redo tail SHALL be truncated.

When the stack is non-empty after popping (nested close), the popped group's operations SHALL be merged into the parent group. If the parent group has no `actionName` and the nested group does, the nested group's `actionName` SHALL be promoted to the parent.

#### Scenario: Top-level group commits to history
- **WHEN** `beginUndoGroup` is called, an operation is recorded, and `endUndoGroup` is called
- **THEN** `canUndo` SHALL be `true` and `undoableCount` SHALL be `1`

#### Scenario: Nested group merges into parent
- **WHEN** an outer group is opened, an inner group is opened with one operation, the inner group is closed, and then the outer group is closed
- **THEN** the committed group SHALL contain the inner group's operation and `undoableCount` SHALL be `1`

#### Scenario: Nested group promotes action name to parent
- **WHEN** an outer group is opened with no `actionName`, an inner group is opened with `actionName: "Typing"`, the inner group is closed, and the outer group is closed
- **THEN** `undoActionName` SHALL be `"Typing"`

#### Scenario: Parent keeps its own action name over nested
- **WHEN** an outer group is opened with `actionName: "Paste"`, an inner group is opened with `actionName: "Typing"`, the inner group is closed, and the outer group is closed
- **THEN** `undoActionName` SHALL be `"Paste"`

#### Scenario: isGrouping reflects open groups
- **WHEN** `beginUndoGroup` is called
- **THEN** `isGrouping` SHALL be `true`
- **WHEN** `endUndoGroup` is then called
- **THEN** `isGrouping` SHALL be `false`

---

### Requirement: Redo tail truncation on new edit
When a new top-level group is committed to history and there are redoable groups (cursor < history count), all redoable groups SHALL be discarded (the redo tail is truncated).

#### Scenario: Edit after undo discards redo stack
- **WHEN** a group is committed, undo is performed, and a new group is committed
- **THEN** `canRedo` SHALL be `false` and `undoableCount` SHALL be `1`

#### Scenario: Multiple undos then new edit discards entire redo tail
- **WHEN** three groups are committed, undo is performed twice, and a new group is committed
- **THEN** `canRedo` SHALL be `false` and `undoableCount` SHALL be `2` (one remaining from original + one new)

---

### Requirement: Undo applies inverse operations
`undo(on:)` SHALL move the cursor back by one, apply the inverse of each operation in the undone group in reverse order on the provided buffer, and return the group's `selectionBefore`.

The inverse of each operation kind:
- `insert(content, at)` → delete the range `NSRange(location: at, length: content.utf16.count)`
- `delete(range, deletedContent)` → insert `deletedContent` at `range.location`
- `replace(range, oldContent, newContent)` → replace the range occupied by `newContent` with `oldContent`

If the buffer is not in the expected state for an inverse operation, a `preconditionFailure` SHALL occur.

Calling `undo(on:)` when `canUndo` is `false` SHALL return `nil` and make no changes.

#### Scenario: Undo single insert
- **WHEN** an insert of `"Hello"` at offset 0 is recorded and committed on a buffer containing `"Hello"`, and `undo(on:)` is called
- **THEN** the buffer content SHALL be `""` and the returned range SHALL be `selectionBefore`

#### Scenario: Undo single delete
- **WHEN** a delete of range `(0,5)` with deletedContent `"Hello"` is recorded and committed on an empty buffer, and `undo(on:)` is called
- **THEN** the buffer content SHALL be `"Hello"` and the returned range SHALL be `selectionBefore`

#### Scenario: Undo multi-operation group in reverse order
- **WHEN** a group contains [insert "A" at 0, insert "B" at 1] on a buffer containing `"AB"`, and `undo(on:)` is called
- **THEN** the inverse of the second operation SHALL be applied first, then the inverse of the first

#### Scenario: Undo when canUndo is false returns nil
- **WHEN** `undo(on:)` is called on a fresh log
- **THEN** the return value SHALL be `nil`

---

### Requirement: Redo reapplies forward operations
`redo(on:)` SHALL move the cursor forward by one, reapply each operation in the redone group in forward order on the provided buffer, and return the group's `selectionAfter`.

Calling `redo(on:)` when `canRedo` is `false` SHALL return `nil` and make no changes.

#### Scenario: Redo after undo restores content
- **WHEN** an insert of `"Hello"` at offset 0 is committed, `undo(on:)` is called, then `redo(on:)` is called
- **THEN** the buffer content SHALL be `"Hello"` and the returned range SHALL be `selectionAfter`

#### Scenario: Redo when canRedo is false returns nil
- **WHEN** `redo(on:)` is called with no undone groups
- **THEN** the return value SHALL be `nil`

---

### Requirement: Undo and redo are proper inverses
Undo followed by redo (or redo followed by undo) SHALL produce zero observable difference in buffer content and selection state. They cancel out completely.

#### Scenario: Undo then redo is identity
- **WHEN** a group is committed producing buffer state S, `undo(on:)` is called, then `redo(on:)` is called
- **THEN** the buffer content and restored selection SHALL be identical to state S

#### Scenario: Redo then undo is identity
- **WHEN** a group is committed, `undo(on:)` is called producing state S, `redo(on:)` is called, then `undo(on:)` is called again
- **THEN** the buffer content and restored selection SHALL be identical to state S

#### Scenario: Multiple undo-redo cycles are stable
- **WHEN** undo and redo are called alternately N times
- **THEN** the buffer content SHALL alternate between exactly two states with no drift

---

### Requirement: canUndo and canRedo state transitions
`canUndo` SHALL be `true` when `cursor > 0` (there are undoable groups). `canRedo` SHALL be `true` when `cursor < history.count` (there are redoable groups). `undoableCount` SHALL equal `cursor`.

#### Scenario: After commit, canUndo is true
- **WHEN** one group is committed
- **THEN** `canUndo` SHALL be `true` and `canRedo` SHALL be `false`

#### Scenario: After undo, canRedo is true
- **WHEN** one group is committed and then undone
- **THEN** `canUndo` SHALL be `false` and `canRedo` SHALL be `true`

#### Scenario: After undo and redo, canRedo is false
- **WHEN** one group is committed, undone, and then redone
- **THEN** `canUndo` SHALL be `true` and `canRedo` SHALL be `false`

---

### Requirement: Action name access
`undoActionName` SHALL return the `actionName` of the group at `cursor - 1` (the next group to undo), or `nil` if `canUndo` is `false`. `redoActionName` SHALL return the `actionName` of the group at `cursor` (the next group to redo), or `nil` if `canRedo` is `false`. `actionName(at:)` SHALL return the `actionName` of the group at the given index, or `nil` if the index is out of bounds.

#### Scenario: undoActionName reflects the last committed group
- **WHEN** a group is committed with `actionName: "Typing"`
- **THEN** `undoActionName` SHALL be `"Typing"`

#### Scenario: redoActionName reflects the undone group
- **WHEN** a group with `actionName: "Typing"` is committed and then undone
- **THEN** `redoActionName` SHALL be `"Typing"`

#### Scenario: undoActionName is nil when canUndo is false
- **WHEN** a fresh `OperationLog` is queried
- **THEN** `undoActionName` SHALL be `nil`

---

### Requirement: Value-type copy independence
`OperationLog` SHALL be a value type. Copying an `OperationLog` via assignment SHALL produce an independent copy. Mutations to the copy (recording, undo, redo) SHALL NOT affect the original, and vice versa.

#### Scenario: Copy then mutate original
- **WHEN** a log with one committed group is copied via `let copy = log`, and then a new group is committed on the original
- **THEN** `copy.undoableCount` SHALL still be `1` and `log.undoableCount` SHALL be `2`

#### Scenario: Undo on copy does not affect original
- **WHEN** a log with one committed group is copied, and `undo(on:)` is called on the copy
- **THEN** `copy.canUndo` SHALL be `false` and `log.canUndo` SHALL be `true`
