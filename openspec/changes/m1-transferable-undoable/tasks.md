## 1. TransferableUndoable scaffold and Buffer conformance

- [ ] 1.1 Create `Sources/TextBuffer/Buffer/TransferableUndoable.swift` with the class shell: `@MainActor public final class TransferableUndoable<Base: Buffer>: Buffer` with stored `base` and `log` properties, `init(_ base: Base)`, and all read-through `Buffer` properties (`content`, `range`, `selectedRange`, `content(in:)`, `unsafeCharacter(at:)`)
- [ ] 1.2 Write tests in `Tests/TextBufferTests/TransferableUndoableTests.swift` verifying read-through behavior: `content`, `range`, `content(in:)`, `selectedRange` get/set all delegate to the wrapped `MutableStringBuffer`

## 2. Mutation recording with auto-grouping

- [ ] 2.1 Implement `insert(_:at:)` with the auto-group pattern: check `log.isGrouping`, wrap in `beginUndoGroup`/`endUndoGroup` if not, delegate to base, record to log
- [ ] 2.2 Implement `delete(in:)` with the same auto-group pattern, capturing old content before deletion for the operation record
- [ ] 2.3 Implement `replace(range:with:)` with the same auto-group pattern
- [ ] 2.4 Implement `modifying(affectedRange:_:)` with auto-group pattern — capture content in affected range before block, delegate to base, record replace operation
- [ ] 2.5 Write tests verifying each mutation method records an undoable operation (`canUndo` is `true` after each), and that auto-grouping wraps standalone mutations

## 3. Undo grouping

- [ ] 3.1 Implement `undoGrouping(actionName:_:)` — call `log.beginUndoGroup(selectionBefore:actionName:)`, execute block, call `log.endUndoGroup(selectionAfter:)`
- [ ] 3.2 Write tests for single-level grouping: two inserts in one group, single undo reverses both
- [ ] 3.3 Write tests for nested grouping: inner group merges into outer, single undo reverses all
- [ ] 3.4 Write test for action name propagation through `undoGrouping`

## 4. Undo and redo

- [ ] 4.1 Implement `canUndo`, `canRedo`, `undo()`, `redo()` — delegate to `log.undo(on: base)` / `log.redo(on: base)` and restore `selectedRange` from returned value
- [ ] 4.2 Write tests: undo after insert restores content and selection; undo after delete restores content and selection
- [ ] 4.3 Write tests: redo after undo restores content and selection; undo-then-redo is identity
- [ ] 4.4 Write test: redo tail truncation — undo, new edit, `canRedo` is false
- [ ] 4.5 Write tests: undo/redo when nothing to undo/redo are no-ops

## 5. Equivalence testing infrastructure

- [ ] 5.1 Create `Sources/TextBufferTesting/AssertUndoEquivalence.swift` with `BufferStep` enum (insert, delete, replace, select, undo, redo, group cases)
- [ ] 5.2 Implement `assertUndoEquivalence(reference:subject:steps:)` — iterate steps, apply each to both buffers, assert `content` and `selectedRange` equality after every step; `.group` case maps to `undoGrouping` recursively
- [ ] 5.3 Implement convenience `assertUndoEquivalence(initial:steps:)` that creates both buffers from a string

## 6. Undo equivalence drift tests

- [ ] 6.1 Create `Tests/TextBufferTests/UndoEquivalenceDriftTests.swift` with simple insert/undo/redo equivalence test
- [ ] 6.2 Add delete equivalence test (delete then undo)
- [ ] 6.3 Add replace equivalence test (replace then undo then redo)
- [ ] 6.4 Add grouped operations equivalence test (two inserts grouped, undo, redo)
- [ ] 6.5 Add interleaved edits and undos equivalence test (edit, edit, undo, edit, undo, undo)
- [ ] 6.6 Add redo tail truncation equivalence test (insert, undo, new insert, redo is no-op)
- [ ] 6.7 Add selection state equivalence test with `.select` steps verifying `selectedRange` at every intermediate step
