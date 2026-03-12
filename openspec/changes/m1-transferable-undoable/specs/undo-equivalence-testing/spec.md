## ADDED Requirements

### Requirement: BufferStep models all edit operations
`BufferStep` SHALL be a public enum in the `TextBufferTesting` module with cases for `insert(content:at:)`, `delete(range:)`, `replace(range:with:)`, `select(_:)`, `undo`, `redo`, and `group(actionName:steps:)`. The `.group` case SHALL contain nested `BufferStep` arrays for recursive application.

#### Scenario: BufferStep cases cover the full edit vocabulary
- **WHEN** a test constructs a `[BufferStep]` array
- **THEN** it SHALL be possible to express insert, delete, replace, selection changes, undo, redo, and grouped operations

#### Scenario: Group steps support nesting
- **WHEN** a `.group` step contains inner `.group` steps
- **THEN** the structure SHALL be representable without limitation on nesting depth

### Requirement: assertUndoEquivalence compares both implementations step by step
`assertUndoEquivalence` SHALL accept a reference `Undoable<MutableStringBuffer>` and a subject `TransferableUndoable<MutableStringBuffer>` along with a `[BufferStep]` array. It SHALL apply each step to both buffers and assert that `content` and `selectedRange` are identical after every step. If any step produces a divergence, the assertion SHALL fail with a message identifying the step index and the nature of the divergence.

#### Scenario: Matching implementations pass
- **WHEN** `assertUndoEquivalence` is called with steps that produce identical results on both implementations
- **THEN** no assertion failure SHALL occur

#### Scenario: Divergent content fails
- **WHEN** the subject produces different `content` than the reference after a step
- **THEN** an assertion failure SHALL be reported identifying the divergent step

#### Scenario: Divergent selection fails
- **WHEN** the subject produces a different `selectedRange` than the reference after a step
- **THEN** an assertion failure SHALL be reported identifying the divergent step

### Requirement: Convenience initializer from initial string
`assertUndoEquivalence(initial:steps:)` SHALL create both an `Undoable<MutableStringBuffer>` and a `TransferableUndoable<MutableStringBuffer>` from the same initial string, then run equivalence comparison. This eliminates boilerplate in drift tests.

#### Scenario: Convenience wrapper sets up both buffers
- **WHEN** `assertUndoEquivalence(initial: "abc", steps: [...])` is called
- **THEN** both buffers SHALL start with content "abc" and identical initial selection
- **AND** all steps SHALL be applied and compared identically to the two-argument form

### Requirement: Group steps map to undoGrouping on both implementations
When a `.group(actionName:steps:)` step is encountered, `assertUndoEquivalence` SHALL call `undoGrouping(actionName:)` on both the reference and subject buffers, applying inner steps recursively within the block. Content and selection SHALL be asserted after the group completes.

#### Scenario: Grouped operations produce identical undo behavior
- **WHEN** a `.group` step containing two inserts is followed by an `.undo` step
- **THEN** both the reference and subject SHALL have identical content and selection after the undo
- **AND** both inserts SHALL be reversed as a single undo step on both implementations

### Requirement: Simple insert/undo/redo equivalence
Equivalence drift tests SHALL verify that simple insert followed by undo and redo produces identical results on both `Undoable` and `TransferableUndoable`.

#### Scenario: Insert then undo then redo
- **WHEN** steps `[.insert("X", at: 0), .undo, .redo]` are run via `assertUndoEquivalence` on a buffer starting with "abc"
- **THEN** both implementations SHALL produce identical content and selection at every step

### Requirement: Delete equivalence
Equivalence drift tests SHALL verify that delete operations produce identical undo/redo behavior on both implementations.

#### Scenario: Delete then undo
- **WHEN** steps `[.delete(range: NSRange(location: 0, length: 1)), .undo]` are run on a buffer starting with "abc"
- **THEN** both implementations SHALL produce identical content "abc" and identical selection after undo

### Requirement: Replace equivalence
Equivalence drift tests SHALL verify that replace operations produce identical undo/redo behavior on both implementations.

#### Scenario: Replace then undo then redo
- **WHEN** steps `[.replace(range: NSRange(location: 0, length: 3), with: "XYZ"), .undo, .redo]` are run on a buffer starting with "abc"
- **THEN** both implementations SHALL produce identical content and selection at every step

### Requirement: Grouped operations equivalence
Equivalence drift tests SHALL verify that grouped operations undo and redo as a single step identically on both implementations.

#### Scenario: Two inserts grouped then undo
- **WHEN** steps `[.group(actionName: nil, steps: [.insert("A", at: 0), .insert("B", at: 1)]), .undo]` are run
- **THEN** both implementations SHALL produce identical content and selection, with both inserts reversed

### Requirement: Interleaved edits and undos equivalence
Equivalence drift tests SHALL verify that interleaved sequences of edits and undos produce identical results.

#### Scenario: Edit, undo, edit, undo, undo
- **WHEN** steps `[.insert("A", at: 0), .insert("B", at: 1), .undo, .insert("C", at: 1), .undo, .undo]` are run
- **THEN** both implementations SHALL produce identical content and selection at every step

### Requirement: Redo tail truncation equivalence
Equivalence drift tests SHALL verify that performing a new edit after undo truncates the redo stack identically on both implementations.

#### Scenario: Undo then new edit discards redo
- **WHEN** steps `[.insert("A", at: 0), .undo, .insert("B", at: 0), .redo]` are run on a buffer starting with ""
- **THEN** both implementations SHALL agree that `redo` has no effect (redo tail was truncated by the new insert)
- **AND** content and selection SHALL be identical at every step

### Requirement: Selection state equivalence at every step
Equivalence drift tests SHALL assert `selectedRange` equality after every step, not just after the final step. Selection divergence at any intermediate step SHALL cause test failure.

#### Scenario: Selection tracked through edit-undo-redo cycle
- **WHEN** steps include `.select`, mutations, `.undo`, and `.redo` in sequence
- **THEN** `selectedRange` SHALL be identical on both implementations after every single step
