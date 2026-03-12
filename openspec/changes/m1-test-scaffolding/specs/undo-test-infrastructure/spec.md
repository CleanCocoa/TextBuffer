## ADDED Requirements

### Requirement: BufferStep enum covers all buffer operations
The `BufferStep` enum in TextBufferTesting SHALL provide cases for every buffer mutation and undo/redo control operation: `insert(content:at:)`, `delete(range:)`, `replace(range:with:)`, `select(_:)`, `undo`, `redo`, and `group(actionName:steps:)`. The `group` case SHALL contain a nested `[BufferStep]` array to model grouped operations recursively.

#### Scenario: Enum has all required cases
- **WHEN** a test author imports TextBufferTesting
- **THEN** `BufferStep` SHALL expose cases `insert`, `delete`, `replace`, `select`, `undo`, `redo`, and `group`

#### Scenario: Group case contains nested steps
- **WHEN** a `BufferStep.group(actionName: "Typing", steps: [.insert(...), .insert(...)])` value is constructed
- **THEN** the nested steps array SHALL be accessible and contain two insert steps

#### Scenario: Enum is public
- **WHEN** a test target depends on TextBufferTesting
- **THEN** `BufferStep` and all its cases SHALL be accessible without `@testable import`

### Requirement: assertUndoEquivalence function structure
The `assertUndoEquivalence` function SHALL accept an `Undoable<MutableStringBuffer>` reference buffer, a `TransferableUndoable<MutableStringBuffer>` subject buffer, and an array of `BufferStep` values. It SHALL iterate each step, apply the operation to both buffers via static dispatch, and assert that `content` and `selectedRange` are equal on both buffers after every step. The function SHALL support `file:` and `line:` parameters for XCTest source location forwarding.

#### Scenario: Steps applied to both buffers with equality check
- **WHEN** `assertUndoEquivalence` is called with steps `[.insert(content: "A", at: 0), .undo]`
- **THEN** after each step, the function SHALL compare `reference.content == subject.content` and `reference.selectedRange == subject.selectedRange`, failing with XCTAssertEqual if they diverge

#### Scenario: Group steps invoke undoGrouping on both buffers
- **WHEN** a `.group(actionName: "Batch", steps: [...])` step is encountered
- **THEN** the function SHALL call `undoGrouping(actionName:)` on both buffers and apply the inner steps recursively within that grouping closure

#### Scenario: Convenience initializer creates both buffers from a string
- **WHEN** `assertUndoEquivalence(initial: "Hello", steps: [...])` is called
- **THEN** the function SHALL create an `Undoable<MutableStringBuffer>` and a `TransferableUndoable<MutableStringBuffer>` both initialized with "Hello", then run the steps

### Requirement: assertUndoEquivalence is guarded until TransferableUndoable exists
The `assertUndoEquivalence` function body (and any code referencing `TransferableUndoable`) SHALL be guarded with `#if false` or equivalent compile-time guard until `TransferableUndoable` is delivered by a subsequent change. The file MUST compile successfully with the guard in place.

#### Scenario: File compiles without TransferableUndoable
- **WHEN** `swift build` is run before TransferableUndoable exists
- **THEN** `AssertUndoEquivalence.swift` SHALL compile without errors

#### Scenario: Guard is removable
- **WHEN** `TransferableUndoable` becomes available (TASK-005/TASK-006)
- **THEN** removing the `#if false` guard SHALL expose a structurally complete function ready for use

### Requirement: Transfer integration tests document three scenarios
`TransferIntegrationTests.swift` SHALL contain three guarded test methods documenting the transfer scenarios specified in TASKS.md TASK-002:
- **Test A (transfer-out preserves undo):** An editor buffer with edits is snapshot'd; undo on the copy SHALL restore previous state.
- **Test B (transfer-in preserves undo):** An in-memory buffer with changes is represent'd into an editor buffer; undo on the editor SHALL restore the source's previous state.
- **Test C (transitivity):** Content transferred in-memory → represent → snapshot; all three buffers SHALL undo/redo identically.

#### Scenario: Test A — transfer-out preserves undo
- **WHEN** an editor buffer has two inserts, then `snapshot()` is called, then `undo()` is called on the snapshot
- **THEN** the snapshot's content SHALL equal the state after the first insert only

#### Scenario: Test B — transfer-in preserves undo
- **WHEN** an in-memory `TransferableUndoable<MutableStringBuffer>` has edits, and `represent(_:)` is called on an editor's `TransferableUndoable`, then `undo()` is called on the editor
- **THEN** the editor's content SHALL equal the source's state before its last edit

#### Scenario: Test C — transitivity
- **WHEN** content is created in-memory, represent'd into an editor, then snapshot'd back to in-memory
- **THEN** all three buffers (original, editor, snapshot) SHALL produce identical content after the same undo/redo sequence

### Requirement: Transfer integration tests are guarded
All three integration test methods SHALL be wrapped in `#if false` guards. The test file MUST compile and `swift test` MUST pass with no new failures.

#### Scenario: Tests compile but do not execute
- **WHEN** `swift test` is run before the transfer API exists
- **THEN** the guarded test methods SHALL not be compiled or executed, and no test failures SHALL be introduced
