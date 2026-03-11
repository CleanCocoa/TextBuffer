## ADDED Requirements

### Requirement: Operation recording

`TransferableUndoable` SHALL record every `insert`, `delete`, and `replace` mutation as a `BufferOperation` value appended to the current open `UndoGroup` in `OperationLog`. If no group is currently open when a mutation is called, `TransferableUndoable` SHALL automatically open a group (capturing `selectedRange` before the mutation), delegate to the base buffer, record the operation, and immediately close the group (capturing `selectedRange` after). Calling `OperationLog.record` outside any open group SHALL crash with `preconditionFailure`.

#### Scenario: Single mutation auto-groups as one undo step
- **WHEN** `insert("x", at: 0)` is called on a `TransferableUndoable` with no open group
- **THEN** `log.canUndo` is `true`, `log.undoableCount` is `1`, and calling `undo()` removes the inserted text and restores the selection to its state before the insert

#### Scenario: Multiple mutations inside undoGrouping form one step
- **WHEN** `undoGrouping { insert("a", at: 0); insert("b", at: 1) }` is called
- **THEN** `log.undoableCount` is `1`, and a single `undo()` removes both insertions atomically

#### Scenario: Record outside group crashes
- **WHEN** `OperationLog.record` is called when `log.isGrouping` is `false`
- **THEN** a `preconditionFailure` is raised

---

### Requirement: Undo group nesting

`OperationLog` SHALL maintain a grouping stack via `beginUndoGroup`/`endUndoGroup`. Nested calls to `undoGrouping` SHALL merge inner operations into the enclosing group. The outer group's `selectionBefore` SHALL be preserved. The inner group's `actionName` SHALL promote to the parent only if the parent has no `actionName`.

#### Scenario: Nested groups merge into parent
- **WHEN** `undoGrouping(actionName: "outer") { undoGrouping(actionName: "inner") { insert("x", at: 0) } }` is called
- **THEN** `log.undoableCount` is `1`, `log.undoActionName` is `"outer"`, and `undo()` undoes all operations from both levels atomically

#### Scenario: Inner action name promotes when parent has none
- **WHEN** `undoGrouping(actionName: nil) { undoGrouping(actionName: "Typing") { insert("y", at: 0) } }` is called
- **THEN** `log.undoActionName` is `"Typing"`

---

### Requirement: Undo and redo as proper inverses

`OperationLog.undo(on:)` SHALL apply the inverse of each operation in the most recent committed group, in reverse order, and return `selectionBefore`. `OperationLog.redo(on:)` SHALL reapply each operation in the next group, in forward order, and return `selectionAfter`. `TransferableUndoable.undo()` and `TransferableUndoable.redo()` SHALL explicitly restore the returned selection onto `base.selectedRange`. The invariant SHALL hold: undo followed by redo (or redo followed by undo) produces zero observable difference in buffer content or selection.

#### Scenario: Undo restores content and selection
- **WHEN** `insert("hello", at: 0)` is called with `selectedRange` at `{0,0}` before and `{5,0}` after, then `undo()` is called
- **THEN** buffer content equals the pre-insert content and `selectedRange` equals `{0,0}` (the captured `selectionBefore`)

#### Scenario: Redo restores content and selection
- **WHEN** after the undo in the previous scenario, `redo()` is called
- **THEN** buffer content equals the post-insert content and `selectedRange` equals `{5,0}` (the captured `selectionAfter`)

#### Scenario: Undo then redo is identity
- **WHEN** an arbitrary sequence of mutations is performed, then `undo()` is called, then `redo()` is called
- **THEN** buffer content and `selectedRange` are identical to the state after the original mutations

#### Scenario: Redo tail is truncated on new edit after undo
- **WHEN** three inserts are performed, `undo()` is called twice, then a new insert is performed
- **THEN** `log.canRedo` is `false` and `log.undoableCount` is `2` (the two surviving groups)

---

### Requirement: OperationLog value-type independence

`OperationLog` SHALL be a `struct`. Assigning or passing a log by value SHALL produce an independent copy. Mutating one copy SHALL NOT affect any other copy.

#### Scenario: Value copy is independent
- **WHEN** `var copy = log` is created after two undo groups are committed, then `copy.undo(on: bufferA)` is called
- **THEN** `log.canUndo` remains `true` (the original log's cursor is unaffected)

---

### Requirement: TransferableUndoable behavioral equivalence to Undoable

`TransferableUndoable<MutableStringBuffer>` SHALL produce identical buffer content and `selectedRange` as `Undoable<MutableStringBuffer>` when driven by the same `[BufferStep]` sequence, after every step. This SHALL be verified by `assertUndoEquivalence`.

#### Scenario: Equivalence on insert/undo/redo
- **WHEN** `assertUndoEquivalence(initial: "abc", steps: [.insert("x", at: 1), .undo, .redo])` is called
- **THEN** no assertion fails — content and selection match at every step

#### Scenario: Equivalence on grouped operations
- **WHEN** a `BufferStep.group` step drives nested mutations followed by `.undo` on both buffers
- **THEN** no assertion fails at any step

#### Scenario: Equivalence on redo tail truncation
- **WHEN** two inserts, two undos, one new insert are applied to both buffers
- **THEN** both buffers have `canRedo == false` and identical content

---

### Requirement: snapshot() produces an independent transferable copy

`TransferableUndoable.snapshot()` SHALL return a new `TransferableUndoable<MutableStringBuffer>` whose content, `selectedRange`, and `OperationLog` are identical to the source at the moment of the call. After `snapshot()` returns, mutations on the original SHALL NOT affect the copy, and mutations on the copy SHALL NOT affect the original. The copy's undo history SHALL be independently navigable.

#### Scenario: Snapshot content matches source
- **WHEN** `snapshot()` is called on a buffer containing `"hello"` with `selectedRange` `{3,0}`
- **THEN** the returned copy has content `"hello"` and `selectedRange` `{3,0}`

#### Scenario: Snapshot undo history is independent
- **WHEN** two inserts are performed on a buffer, `snapshot()` is called, then `undo()` is called on the copy
- **THEN** the copy's content reflects the undo, and the original's content is unchanged

#### Scenario: Mutating original does not affect copy
- **WHEN** `snapshot()` is called, then `insert("X", at: 0)` is performed on the original
- **THEN** the copy's content does not contain `"X"`

---

### Requirement: represent() replaces all buffer state from a source

`TransferableUndoable.represent(_:)` SHALL replace the receiver's content, `selectedRange`, and `OperationLog` entirely with the source's state. The replacement SHALL NOT be recorded as an undoable operation. After `represent()`, `undo()` on the receiver SHALL undo operations from the source's history (not from the receiver's previous history). `represent()` SHALL `preconditionFailure` if called while `log.isGrouping` is `true`.

#### Scenario: represent() loads source content and selection
- **WHEN** a source buffer contains `"world"` with `selectedRange` `{2,0}` and `represent(source)` is called on a receiver containing `"hello"`
- **THEN** receiver content is `"world"` and `selectedRange` is `{2,0}`

#### Scenario: represent() makes source history undoable on receiver
- **WHEN** source has two committed undo groups, then `represent(source)` is called on receiver
- **THEN** `receiver.canUndo` is `true`, and calling `receiver.undo()` restores the source's previous state

#### Scenario: represent() during open group crashes
- **WHEN** `beginUndoGroup` has been called without a matching `endUndoGroup`, then `represent(_:)` is called
- **THEN** a `preconditionFailure` is raised

#### Scenario: represent() is not itself undoable
- **WHEN** `represent(source)` is called then `undo()` is called
- **THEN** the `undo()` undoes the most recent operation from the source's history, not a hypothetical "represent" action

---

### Requirement: BufferStep-driven equivalence test infrastructure

`TextBufferTesting` SHALL provide a `BufferStep` enum and an `assertUndoEquivalence` function. `BufferStep` SHALL enumerate: `insert(content:at:)`, `delete(range:)`, `replace(range:with:)`, `select(NSRange)`, `undo`, `redo`, `group(actionName:steps:)`. `assertUndoEquivalence` SHALL accept an initial `String`, apply each step to both `Undoable<MutableStringBuffer>` and `TransferableUndoable<MutableStringBuffer>`, and `XCTAssert` content and selection equality after every step.

#### Scenario: All BufferStep cases apply correctly
- **WHEN** a sequence of all `BufferStep` cases is applied via `assertUndoEquivalence`
- **THEN** every step succeeds (no assertion failures) when both implementations behave identically

#### Scenario: Divergence detected immediately
- **WHEN** `TransferableUndoable` has a bug that causes `undo()` to not restore `selectedRange`
- **THEN** `assertUndoEquivalence` fails at the first `.undo` step with a clear selection mismatch message
