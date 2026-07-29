## ADDED Requirements

### Requirement: Undo/redo correctness on rope-backed buffer
`TransferableUndoable<RopeBuffer>` SHALL support undo and redo operations that produce identical content and selection state as the equivalent operations on `TransferableUndoable<MutableStringBuffer>`. Undo MUST reverse mutations by replaying inverse operations through `RopeBuffer`'s `Buffer` conformance. Redo MUST reapply forward operations. Grouped mutations (via `undoGrouping`) MUST undo/redo atomically.

#### Scenario: Single insert then undo
- **WHEN** a `TransferableUndoable<RopeBuffer>` with initial content "Hello" receives `insert("World", at: 5)` followed by `undo()`
- **THEN** content SHALL equal "Hello" and `canUndo` SHALL be false and `canRedo` SHALL be true

#### Scenario: Grouped mutations undo atomically
- **WHEN** a `TransferableUndoable<RopeBuffer>` receives multiple mutations inside a single `undoGrouping` block followed by `undo()`
- **THEN** all mutations within the group SHALL be reversed as a single step

#### Scenario: Undo then redo restores state
- **WHEN** a `TransferableUndoable<RopeBuffer>` receives mutations, then `undo()`, then `redo()`
- **THEN** content and selection SHALL equal the state after the original mutations

#### Scenario: Multi-byte Unicode content undo
- **WHEN** a `TransferableUndoable<RopeBuffer>` with content containing emoji (U+10000+), CJK characters, or combining marks receives mutations and then `undo()`
- **THEN** content SHALL be restored correctly with no corruption at UTF-8/UTF-16 boundaries

### Requirement: Snapshot from rope to string buffer
`TransferableUndoable<RopeBuffer>.snapshot()` SHALL return a `TransferableUndoable<MutableStringBuffer>` that is an independent copy. The snapshot MUST have identical content, identical selected range, and identical undo history. Modifications to the snapshot MUST NOT affect the original, and vice versa.

#### Scenario: Snapshot preserves content and selection
- **WHEN** `snapshot()` is called on a `TransferableUndoable<RopeBuffer>` with content "abc" and selectedRange (1, 2)
- **THEN** the returned `TransferableUndoable<MutableStringBuffer>` SHALL have content "abc" and selectedRange (1, 2)

#### Scenario: Snapshot preserves undo history
- **WHEN** a `TransferableUndoable<RopeBuffer>` has performed mutations and `snapshot()` is called
- **THEN** calling `undo()` on the snapshot SHALL produce the same content as calling `undo()` on the original would

#### Scenario: Snapshot independence
- **WHEN** `snapshot()` is called and the original `TransferableUndoable<RopeBuffer>` subsequently receives new mutations
- **THEN** the snapshot's content and undo history SHALL remain unchanged

#### Scenario: Snapshot with multi-byte content
- **WHEN** `snapshot()` is called on a `TransferableUndoable<RopeBuffer>` containing emoji and CJK text
- **THEN** the snapshot's content SHALL be byte-identical to the original's content, and selectedRange SHALL reference the same UTF-16 positions

### Requirement: Represent from string buffer into rope buffer
`TransferableUndoable<RopeBuffer>.represent(_:)` SHALL accept a `TransferableUndoable<MutableStringBuffer>` (or any `TransferableUndoable<S>` where S conforms to Buffer) and replace the receiver's content, selection, and undo history entirely. After represent, the receiver MUST be independent of the source. The operation MUST NOT be itself undoable.

#### Scenario: Represent loads content and selection
- **WHEN** `represent(_:)` is called on a `TransferableUndoable<RopeBuffer>` with a source containing "new content" and selectedRange (0, 3)
- **THEN** the rope buffer's content SHALL equal "new content" and selectedRange SHALL equal (0, 3)

#### Scenario: Represent loads undo history
- **WHEN** `represent(_:)` is called with a source that has undo history, then `undo()` is called on the receiver
- **THEN** the undo SHALL replay correctly through the rope buffer, producing the expected prior content

#### Scenario: Represent replaces previous state entirely
- **WHEN** a `TransferableUndoable<RopeBuffer>` has existing content "old" and undo history, then `represent(_:)` is called with a source containing "new"
- **THEN** content SHALL equal "new" and the previous undo history SHALL be discarded — only the source's undo history SHALL be available

#### Scenario: Represent with multi-byte content
- **WHEN** `represent(_:)` is called with a source containing emoji, combining marks, and CJK text
- **THEN** the rope buffer's content SHALL be identical to the source's content with no UTF-8/UTF-16 translation errors

### Requirement: Cross-type transfer round-trip
A complete round-trip — `snapshot()` from `TransferableUndoable<RopeBuffer>` to `TransferableUndoable<MutableStringBuffer>`, then `represent(_:)` back into a `TransferableUndoable<RopeBuffer>` — SHALL preserve content, selection, and undo history exactly. Multiple round-trips MUST be idempotent with respect to observable state.

#### Scenario: Rope → String → Rope round-trip preserves state
- **WHEN** a `TransferableUndoable<RopeBuffer>` with content and undo history calls `snapshot()`, and the snapshot is then passed to `represent(_:)` on a fresh `TransferableUndoable<RopeBuffer>`
- **THEN** the target SHALL have identical content, selection, and undo behavior as the original

#### Scenario: Round-trip preserves undo/redo after transfer
- **WHEN** after a round-trip transfer, `undo()` is called on the target `TransferableUndoable<RopeBuffer>`
- **THEN** content SHALL match what `undo()` would have produced on the original before snapshot

#### Scenario: Multiple round-trips are idempotent
- **WHEN** a `TransferableUndoable<RopeBuffer>` undergoes two consecutive snapshot → represent round-trips
- **THEN** content, selection, and undo history SHALL be identical after the second round-trip as after the first

### Requirement: Undo equivalence across buffer types
Identical `BufferStep` sequences applied to `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>` SHALL produce identical content and selection after every step. This equivalence MUST hold for all operation types: insert, delete, replace, select, undo, redo, and grouped operations.

#### Scenario: Simple edit sequence equivalence
- **WHEN** a sequence of insert, delete, and replace steps is applied to both `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>` starting from the same initial content
- **THEN** content and selectedRange SHALL be equal after every step

#### Scenario: Undo/redo interleaved with edits equivalence
- **WHEN** a sequence mixing mutations, undo, redo, and further mutations is applied to both buffer types
- **THEN** content and selectedRange SHALL be equal after every step, including after undo clears the redo stack

#### Scenario: Grouped operations equivalence
- **WHEN** a sequence containing `BufferStep.group` with nested operations is applied to both buffer types
- **THEN** content and selectedRange SHALL be equal after every step, and `undo()` SHALL reverse the group atomically on both

#### Scenario: Multi-byte Unicode sequence equivalence
- **WHEN** a sequence involving insertions and deletions of emoji (surrogate pairs), CJK characters, and combining mark sequences is applied to both buffer types
- **THEN** content and selectedRange SHALL be equal after every step, confirming UTF-8/UTF-16 translation consistency

### Requirement: Three buffer types interchangeable via transfer API
The transfer API (`snapshot()` and `represent(_:)`) SHALL enable any `TransferableUndoable<T>` to exchange state with any `TransferableUndoable<U>` through the `MutableStringBuffer` intermediary produced by `snapshot()`. Specifically, `TransferableUndoable<RopeBuffer>`, `TransferableUndoable<MutableStringBuffer>`, and any future `TransferableUndoable<Base>` MUST be able to snapshot and represent interchangeably.

#### Scenario: RopeBuffer snapshot consumed by MutableStringBuffer represent
- **WHEN** `TransferableUndoable<RopeBuffer>` calls `snapshot()` and the result is passed to `represent(_:)` on a `TransferableUndoable<MutableStringBuffer>`
- **THEN** the `MutableStringBuffer`-backed instance SHALL have identical content, selection, and undo history

#### Scenario: MutableStringBuffer snapshot consumed by RopeBuffer represent
- **WHEN** `TransferableUndoable<MutableStringBuffer>` calls `snapshot()` and the result is passed to `represent(_:)` on a `TransferableUndoable<RopeBuffer>`
- **THEN** the `RopeBuffer`-backed instance SHALL have identical content, selection, and undo history

#### Scenario: Three-way exchange
- **WHEN** content originates in `TransferableUndoable<RopeBuffer>`, is snapshotted to `TransferableUndoable<MutableStringBuffer>`, mutated there, snapshotted again, and represented into a second `TransferableUndoable<RopeBuffer>`
- **THEN** the final rope buffer SHALL reflect all mutations including those performed on the string buffer, with full undo history
