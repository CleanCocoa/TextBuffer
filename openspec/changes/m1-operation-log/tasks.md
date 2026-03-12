## 1. BufferOperation and UndoGroup (TASK-003)

- [ ] 1.1 Create `Sources/TextBuffer/OperationLog/BufferOperation.swift` — `BufferOperation` struct with `Kind` enum (insert/delete/replace), conforming to `Sendable` and `Equatable`
- [ ] 1.2 Create `Sources/TextBuffer/OperationLog/UndoGroup.swift` — `UndoGroup` struct with `operations`, `selectionBefore`, `selectionAfter`, `actionName`, conforming to `Sendable` and `Equatable`
- [ ] 1.3 Verify both types compile and Equatable works (build the target)

## 2. OperationLog Core Structure (TASK-004)

- [ ] 2.1 Create `Sources/TextBuffer/OperationLog/OperationLog.swift` — `OperationLog` struct with `history`, `cursor`, `groupingStack`, `init()`, `isGrouping`, conforming to `Sendable` and `Equatable`
- [ ] 2.2 Implement `beginUndoGroup(selectionBefore:actionName:)` and `endUndoGroup(selectionAfter:)` with nested-group merge semantics and action name promotion
- [ ] 2.3 Implement `record(_:)` with preconditionFailure when no group is open
- [ ] 2.4 Implement `canUndo`, `canRedo`, `undoableCount`, `undoActionName`, `redoActionName`, `actionName(at:)` computed properties
- [ ] 2.5 Implement redo tail truncation in `endUndoGroup` when committing a top-level group with `cursor < history.count`

## 3. Undo and Redo (TASK-004)

- [ ] 3.1 Implement `undo(on:)` — decrement cursor, apply inverse operations in reverse order, return `selectionBefore`; return nil if `canUndo` is false
- [ ] 3.2 Implement `redo(on:)` — increment cursor, reapply operations in forward order, return `selectionAfter`; return nil if `canRedo` is false

## 4. Tests (TASK-004)

- [ ] 4.1 Create `Tests/TextBufferTests/OperationLogTests.swift` with test helper to create a `MutableStringBuffer` and convenience methods for committing groups
- [ ] 4.2 Test single insert operation undo/redo round-trip
- [ ] 4.3 Test single delete operation undo/redo round-trip
- [ ] 4.4 Test single replace operation undo/redo round-trip
- [ ] 4.5 Test multi-operation group undo/redo
- [ ] 4.6 Test nested groups merge into parent
- [ ] 4.7 Test action name propagation — nested promotes to parent when parent has none; parent keeps its own over nested
- [ ] 4.8 Test redo tail truncation on new edit after undo
- [ ] 4.9 Test `canUndo`/`canRedo` state transitions across commit, undo, redo sequences
- [ ] 4.10 Test `selectionBefore` restored on undo, `selectionAfter` restored on redo
- [ ] 4.11 Test undo→redo = identity and redo→undo = identity (ADR-009 inverse invariant)
- [ ] 4.12 Test value-type copy independence — mutating copy does not affect original
- [ ] 4.13 Test `record` outside a group triggers preconditionFailure
