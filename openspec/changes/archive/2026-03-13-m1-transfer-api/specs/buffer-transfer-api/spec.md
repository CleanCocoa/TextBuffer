## ADDED Requirements

### Requirement: snapshot creates independent copy
`TransferableUndoable.snapshot()` SHALL return a new `TransferableUndoable<MutableStringBuffer>` containing the same content, selection, and undo history as the original. The returned copy MUST be fully independent — no shared mutable state with the original.

#### Scenario: Snapshot copies content and selection
- **WHEN** a TransferableUndoable with content "Hello" and selectedRange (2,3) calls `snapshot()`
- **THEN** the returned buffer's `content` SHALL equal "Hello"
- **AND** its `selectedRange` SHALL equal (2,3)

#### Scenario: Snapshot copies undo history
- **WHEN** a TransferableUndoable has performed edits in undo groups and calls `snapshot()`
- **THEN** the returned buffer's `canUndo` SHALL equal the original's `canUndo`
- **AND** calling `undo()` on the snapshot SHALL restore the same prior state as undoing on the original

#### Scenario: Mutating snapshot does not affect original
- **WHEN** a snapshot is created and then mutated (insert, delete, or replace)
- **THEN** the original buffer's content and undo history SHALL remain unchanged

#### Scenario: Mutating original does not affect snapshot
- **WHEN** a snapshot is created and then the original is mutated
- **THEN** the snapshot's content and undo history SHALL remain unchanged

### Requirement: snapshot return type is MutableStringBuffer-backed
`snapshot()` SHALL always return `TransferableUndoable<MutableStringBuffer>` regardless of the source buffer's `Base` type. Content MUST be copied via `MutableStringBuffer(wrapping:)`.

#### Scenario: Snapshot of any Buffer type returns MutableStringBuffer wrapper
- **WHEN** `snapshot()` is called on a `TransferableUndoable<Base>` where Base is any Buffer conformer
- **THEN** the return type SHALL be `TransferableUndoable<MutableStringBuffer>`
- **AND** the content SHALL be an in-memory copy

### Requirement: represent replaces entire state
`TransferableUndoable.represent(_:)` SHALL replace the receiver's content, selection, and undo history entirely with the source's state. The receiver's previous state MUST be discarded. This operation is not itself undoable.

#### Scenario: Represent replaces content and selection
- **WHEN** a buffer with content "Old" calls `represent(source)` where source has content "New" and selectedRange (1,2)
- **THEN** the receiver's `content` SHALL equal "New"
- **AND** its `selectedRange` SHALL equal (1,2)

#### Scenario: Represent replaces undo history
- **WHEN** a buffer with its own undo history calls `represent(source)` where source has two undoable groups
- **THEN** the receiver's `canUndo` SHALL be true
- **AND** calling `undo()` SHALL undo the source's most recent group (not the receiver's old history)

#### Scenario: Represent discards receiver's previous undo state
- **WHEN** a buffer with three undoable groups calls `represent(source)` where source has one undoable group
- **THEN** the receiver SHALL only be able to undo once (the source's single group)
- **AND** the receiver's previous three groups SHALL be unreachable

#### Scenario: Represent then undo then redo
- **WHEN** a buffer calls `represent(source)`, then `undo()`, then `redo()`
- **THEN** after undo, the content SHALL match the source's state before its last edit
- **AND** after redo, the content SHALL match the source's current state

### Requirement: represent produces independent copy of log
After `represent(_:)`, the receiver and source MUST have independent undo histories. Mutations to either side's log SHALL NOT affect the other.

#### Scenario: Undo on receiver after represent does not affect source
- **WHEN** a buffer calls `represent(source)` and then calls `undo()`
- **THEN** the source's content and undo state SHALL remain unchanged

#### Scenario: Mutating source after represent does not affect receiver
- **WHEN** a buffer calls `represent(source)` and then the source is mutated
- **THEN** the receiver's content and undo history SHALL remain unchanged

### Requirement: represent precondition on open group
`represent(_:)` MUST call `precondition(!log.isGrouping)`. Calling `represent()` while an undo group is open is a programming error and SHALL trap.

#### Scenario: Represent while undo group is open traps
- **WHEN** `represent(source)` is called while `log.isGrouping` is true (inside an `undoGrouping` block)
- **THEN** the call SHALL trigger a precondition failure

#### Scenario: Represent outside undo group succeeds
- **WHEN** `represent(source)` is called with no open undo group
- **THEN** the call SHALL complete successfully and replace the receiver's state
