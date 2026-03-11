## ADDED Requirements

### Requirement: TransferableUndoable<RopeBuffer> supports undo and redo
`TransferableUndoable<RopeBuffer>` SHALL record all `insert`, `delete`, and `replace` operations into its `OperationLog` and support `undo()` and `redo()` that restore exact content and `selectedRange` values. This requirement verifies that `TransferableUndoable` composes correctly with `RopeBuffer` as its `Base`.

#### Scenario: Single insert is undoable
- **WHEN** `insert("hello", at: 0)` is called on a `TransferableUndoable<RopeBuffer>` wrapping an empty buffer
- **THEN** `canUndo` is `true`, `content` is `"hello"`
- **WHEN** `undo()` is called
- **THEN** `content` is `""` and `selectedRange` is restored to its value before the insert

#### Scenario: Grouped operations undo as one step
- **WHEN** `undoGrouping { insert("a", at: 0); insert("b", at: 1) }` is called
- **THEN** `canUndo` is `true` and `undoableCount` is `1`
- **WHEN** `undo()` is called
- **THEN** both insertions are reversed and content returns to its pre-group state

#### Scenario: Undo then redo restores content and selection exactly
- **WHEN** an edit is performed, then `undo()`, then `redo()`
- **THEN** `content` and `selectedRange` are identical to their values immediately after the original edit (undo and redo are proper inverses per ADR-009)

#### Scenario: Redo tail is truncated by new edit after undo
- **WHEN** two edits are made, `undo()` is called once, then a new edit is made
- **THEN** `canRedo` is `false`

---

### Requirement: snapshot() transfers rope-backed state to a MutableStringBuffer
`TransferableUndoable<RopeBuffer>.snapshot()` SHALL return a `TransferableUndoable<MutableStringBuffer>` with content, `selectedRange`, and a fully independent copy of the `OperationLog` from the source. After the snapshot is taken, mutations on either the original or the copy SHALL NOT affect the other.

#### Scenario: Snapshot content matches source
- **WHEN** a `TransferableUndoable<RopeBuffer>` containing `"hello"` with `selectedRange` at position 3 calls `snapshot()`
- **THEN** the returned buffer's `content` is `"hello"` and `selectedRange.location` is `3`

#### Scenario: Snapshot undo history is independent
- **WHEN** a `TransferableUndoable<RopeBuffer>` with two undo steps calls `snapshot()`
- **THEN** `undo()` on the snapshot restores the previous state on the snapshot only; the original rope-backed buffer is unaffected

#### Scenario: Undo on snapshot after transfer-out produces correct state
- **WHEN** a rope-backed buffer is edited twice, `snapshot()` is called, then `undo()` is called on the snapshot
- **THEN** the snapshot's `content` matches what the rope-backed buffer's content was after the first (not second) edit

#### Scenario: Mutating the snapshot does not affect the original
- **WHEN** `snapshot()` produces a copy, then `insert("x", at: 0)` is called on the copy
- **THEN** the original rope-backed buffer's `content` is unchanged

---

### Requirement: represent() loads MutableStringBuffer state into a RopeBuffer
`TransferableUndoable<RopeBuffer>.represent(_:)` SHALL accept a `TransferableUndoable<MutableStringBuffer>` as source, replace the rope-backed buffer's content and `selectedRange`, and copy the source's `OperationLog`. After `represent()`, `undo()` on the rope-backed buffer SHALL replay the source's prior edit history.

#### Scenario: represent() replaces content
- **WHEN** `represent(source)` is called where `source.content` is `"world"` and the rope buffer contains `"hello"`
- **THEN** the rope buffer's `content` is `"world"`

#### Scenario: represent() replaces selection
- **WHEN** `represent(source)` is called where `source.selectedRange` is `NSRange(location: 2, length: 3)`
- **THEN** the rope buffer's `selectedRange` is `NSRange(location: 2, length: 3)`

#### Scenario: Undo after represent() reproduces the source's prior undo state
- **WHEN** a `TransferableUndoable<MutableStringBuffer>` has had one edit (so `canUndo` is `true`) and `represent()` loads it into a rope-backed buffer
- **THEN** calling `undo()` on the rope-backed buffer produces the same content and selection state that `undo()` on the source would have produced at the moment of representation

#### Scenario: represent() precondition: no open undo group
- **WHEN** `represent()` is called while an undo group is open on the rope-backed buffer
- **THEN** a `preconditionFailure` is triggered (programming error; document switch must not occur mid-edit-group)

---

### Requirement: Buffer types are interchangeable via snapshot and represent
For any pair of `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>` carrying the same edit history, `snapshot()` and `represent()` SHALL produce equivalent undo/redo behaviour regardless of which buffer type executes the operations. The three transitivity scenarios from the original transfer integration tests SHALL hold when the editor is rope-backed.

#### Scenario: Transfer-out preserves undo (rope variant)
- **WHEN** a `TransferableUndoable<RopeBuffer>` has two edits, `snapshot()` produces a string-backed copy, and `undo()` is called on the copy
- **THEN** the copy's content matches the rope buffer's content after only the first edit

#### Scenario: Transfer-in preserves undo (rope target)
- **WHEN** a `TransferableUndoable<MutableStringBuffer>` has two edits and `represent()` loads it into a `TransferableUndoable<RopeBuffer>`, then `undo()` is called on the rope-backed buffer
- **THEN** the rope-backed buffer's content matches what the string-backed buffer contained after only the first edit

#### Scenario: Transitivity — rope as intermediary
- **WHEN** a string-backed buffer is represented into a rope-backed buffer via `represent()`, then `snapshot()` is called on the rope-backed buffer to produce a second string-backed copy
- **THEN** `undo()` on the original string-backed source, the rope-backed intermediary, and the final string-backed copy all produce the same content

---

### Requirement: RopeBuffer and MutableStringBuffer produce equivalent undo sequences
For any `BufferStep` sequence applied to both `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>` via a dedicated cross-type helper using static dispatch, the content and `selectedRange` SHALL be identical after every step — including `undo`, `redo`, and `group` steps.

#### Scenario: Cross-type transferable-undo equivalence passes for insert/undo/redo
- **WHEN** the dedicated cross-type helper is run with steps `[.insert("x", at: 0), .undo, .redo]` on a rope-backed subject and a string-backed reference
- **THEN** all assertions pass: content and selection match at every step

#### Scenario: Cross-type transferable-undo equivalence passes for grouped edits
- **WHEN** the dedicated cross-type helper is run with a `.group` step containing multiple inserts, followed by `.undo`
- **THEN** both buffer types undo to the same pre-group state

#### Scenario: Cross-type transferable-undo equivalence passes for redo-tail truncation
- **WHEN** two edits are made, one undo is performed, then a new edit — applied identically to both buffer types via the dedicated cross-type helper
- **THEN** `canRedo` is `false` on both and content matches
