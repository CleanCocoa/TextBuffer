## ADDED Requirements

### Requirement: Transfer-out preserves undo on original
After calling `snapshot()`, the original buffer's undo/redo capability SHALL remain fully functional. The snapshot operation MUST NOT interfere with the original's undo history.

#### Scenario: Undo on original after snapshot
- **WHEN** a TransferableUndoable performs edits in groups, calls `snapshot()`, then calls `undo()` on the original
- **THEN** the original's content SHALL revert to the state before the last group
- **AND** the snapshot's content SHALL remain at the state when the snapshot was taken

#### Scenario: Redo on original after snapshot
- **WHEN** a TransferableUndoable performs edits, calls `snapshot()`, calls `undo()` then `redo()` on the original
- **THEN** the original's content SHALL return to the state before undo was called
- **AND** the snapshot SHALL remain unaffected

### Requirement: Transfer-in preserves undo from source
After calling `represent(source)`, calling `undo()` on the receiver SHALL undo the source's most recent edit group, restoring the state the source had before that edit.

#### Scenario: Undo after represent restores source's prior state
- **WHEN** a source buffer has content "AB" from two groups (first inserted "A", second inserted "B"), and a receiver calls `represent(source)`, then `undo()`
- **THEN** the receiver's content SHALL equal the source's state after only the first group (i.e., "A")

#### Scenario: Full undo chain after represent
- **WHEN** a source buffer has three undo groups and a receiver calls `represent(source)`, then calls `undo()` three times
- **THEN** each undo SHALL restore the corresponding prior state from the source's history
- **AND** `canUndo` SHALL be false after the third undo

### Requirement: Transfer is transitive
Transferring A→B→C SHALL produce three independent buffers. Each buffer's content and undo history MUST be independent of the others.

#### Scenario: A to B to C transfer chain
- **WHEN** buffer A performs edits, B calls `represent(A)`, B performs additional edits, C calls `represent(B)`
- **THEN** C SHALL have B's full history (A's original edits plus B's additional edits)
- **AND** undoing on C SHALL NOT affect A or B
- **AND** undoing on B SHALL NOT affect A or C

#### Scenario: Snapshot chain A→B→C
- **WHEN** buffer A calls `snapshot()` to create B, then B calls `snapshot()` to create C
- **THEN** A, B, and C SHALL all have identical content and undo history at that point
- **AND** mutating any one SHALL NOT affect the other two

### Requirement: Snapshot during active puppet bridge
Calling `snapshot()` while a PuppetUndoManager is active on the source SHALL succeed. The snapshot MUST NOT share the PuppetUndoManager — it SHALL have its own independent undo mechanism. The source's puppet bridge MUST continue to function normally after the snapshot.

#### Scenario: Snapshot with puppet bridge active
- **WHEN** a TransferableUndoable has called `enableSystemUndoIntegration()` and then calls `snapshot()`
- **THEN** the snapshot SHALL contain the correct content, selection, and undo history
- **AND** the source's PuppetUndoManager SHALL remain functional (canUndo/canRedo unchanged)
- **AND** the snapshot SHALL NOT have a PuppetUndoManager installed

#### Scenario: Undo via puppet after snapshot
- **WHEN** a TransferableUndoable with an active puppet bridge calls `snapshot()`, then undoes via the puppet
- **THEN** the undo SHALL apply to the original buffer only
- **AND** the snapshot's state SHALL remain unchanged

### Requirement: Represent replaces previous undo state entirely
When `represent(source)` is called, the receiver's entire previous undo history SHALL be discarded and replaced by the source's history. The source's history becomes the only undoable history on the receiver.

#### Scenario: Previous undo history is unreachable after represent
- **WHEN** a receiver has performed 5 undo groups, then calls `represent(source)` where source has 2 undo groups
- **THEN** the receiver SHALL only be able to undo 2 times (the source's groups)
- **AND** the receiver's original 5 groups SHALL be permanently discarded

#### Scenario: Represent then undo shows source history not receiver history
- **WHEN** a receiver with content "Receiver" calls `represent(source)` where source has content "Source" built from two edits, then calls `undo()`
- **THEN** the content SHALL reflect undoing the source's last edit
- **AND** the content SHALL NOT revert to "Receiver" at any undo depth
