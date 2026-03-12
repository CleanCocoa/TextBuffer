## 1. Transfer API — snapshot (TASK-008a)

- [ ] 1.1 Write failing tests for `snapshot()` in `TransferAPITests.swift`: snapshot copies content and selection, snapshot copies undo history, mutating snapshot does not affect original, mutating original does not affect snapshot
- [ ] 1.2 Implement `snapshot()` on `TransferableUndoable` — create `MutableStringBuffer(wrapping: base)`, copy log via value-type assignment, return new `TransferableUndoable<MutableStringBuffer>`

## 2. Transfer API — represent (TASK-008b)

- [ ] 2.1 Write failing tests for `represent(_:)` in `TransferAPITests.swift`: represent replaces content and selection, represent replaces undo history, represent discards receiver's previous undo state, represent then undo then redo round-trip, independence after represent (receiver undo doesn't affect source, source mutation doesn't affect receiver)
- [ ] 2.2 Implement `represent(_:)` on `TransferableUndoable` — precondition `!log.isGrouping`, replace content via `base.replace(range:with:)`, set selection, copy source log
- [ ] 2.3 Write test for represent precondition: calling `represent()` inside `undoGrouping` block traps (use `expectation` or documented precondition-testing pattern)

## 3. Integration Tests — Core Transfer Scenarios (TASK-009a)

- [ ] 3.1 Unguard and complete Test A: transfer-out preserves undo — snapshot then undo/redo on original, verify snapshot unchanged
- [ ] 3.2 Unguard and complete Test B: transfer-in preserves undo — represent a source then undo on receiver, verify source's history is applied
- [ ] 3.3 Unguard and complete Test C: transitivity — A→B→C transfer chain, verify all three buffers are independent

## 4. Integration Tests — Additional Cases (TASK-009b)

- [ ] 4.1 Write test: snapshot during active puppet bridge — call `enableSystemUndoIntegration()`, snapshot, verify snapshot has correct state, verify puppet still works on original, verify snapshot has no puppet
- [ ] 4.2 Write test: represent discards previous undo state entirely — receiver with N groups calls represent(source) with M groups, verify only M undos available, old history unreachable
- [ ] 4.3 Run full test suite (`swift test`) and verify all transfer API and integration tests pass
