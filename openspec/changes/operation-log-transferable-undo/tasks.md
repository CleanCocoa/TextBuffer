## 1. Test Infrastructure (TASK-001, TASK-002)

- [ ] 1.1 Create `Sources/TextBufferTesting/BufferStep.swift` — define the `BufferStep` enum with all cases: `insert(content:at:)`, `delete(range:)`, `replace(range:with:)`, `select(NSRange)`, `undo`, `redo`, `group(actionName:steps:)`
- [ ] 1.2 Create `Sources/TextBufferTesting/AssertUndoEquivalence.swift` — stub `assertUndoEquivalence(reference:subject:steps:file:line:)` and the convenience wrapper `assertUndoEquivalence(initial:steps:)`. Guard the body with `#if false` until `TransferableUndoable` exists. Verify the file compiles.
- [ ] 1.3 Create `Tests/TextBufferTests/TransferIntegrationTests.swift` — write three guarded integration tests: (A) transfer-out preserves undo, (B) transfer-in preserves undo, (C) transitivity. Mark each with `// TODO: unguard in TASK-009`.

## 2. Core Value Types (TASK-003, TASK-004)

- [ ] 2.1 Create `Sources/TextBuffer/OperationLog/BufferOperation.swift` — implement `BufferOperation` struct with `Kind` enum (`insert(content:at:)`, `delete(range:NSRange, deletedContent:String)`, `replace(range:NSRange, oldContent:String, newContent:String)`). Conform to `Sendable` and `Equatable`.
- [ ] 2.2 Create `Sources/TextBuffer/OperationLog/UndoGroup.swift` — implement `UndoGroup` struct with `operations: [BufferOperation]`, `selectionBefore: NSRange`, `selectionAfter: NSRange?`, `actionName: String?`. Conform to `Sendable` and `Equatable`.
- [ ] 2.3 Create `Sources/TextBuffer/OperationLog/OperationLog.swift` — implement the `OperationLog` struct: `history: [UndoGroup]`, `cursor: Int`, `groupingStack: [UndoGroup]`, `isGrouping: Bool`, `beginUndoGroup(selectionBefore:actionName:)`, `endUndoGroup(selectionAfter:)`, `record(_:)`. Commit to history on top-level `endUndoGroup`; merge into parent on nested close. `record` outside a group is `preconditionFailure`.
- [ ] 2.4 Add `canUndo`, `canRedo`, `undoableCount`, `undoActionName`, `redoActionName`, `actionName(at:)` computed properties to `OperationLog`.
- [ ] 2.5 Implement `OperationLog.undo(on:)` and `OperationLog.redo(on:)` — apply inverse/forward operations and return `selectionBefore` / `selectionAfter` for the caller to restore. `TransferableUndoable.undo()` / `redo()` apply the returned selection to `base.selectedRange`. Inverse failures are `preconditionFailure`.
- [ ] 2.6 Create `Tests/TextBufferTests/OperationLogTests.swift` — write unit tests covering: single-op undo/redo round-trip, multi-op group, nested groups merge, redo tail truncation, canUndo/canRedo transitions, action name propagation, selectionBefore/After restoration, undo→redo identity, value-type copy independence.

## 3. TransferableUndoable Core (TASK-005)

- [ ] 3.1 Create `Sources/TextBuffer/Buffer/TransferableUndoable.swift` — declare `@MainActor public final class TransferableUndoable<Base: Buffer>` conforming to `Buffer` where `Base.Range == NSRange, Base.Content == String`. Add stored properties: `base: Base`, `log: OperationLog`, `puppetUndoManager: PuppetUndoManager?`.
- [ ] 3.2 Implement `Buffer` protocol requirements on `TransferableUndoable`: `content`, `range`, `selectedRange` (get/set), `content(in:)`, `unsafeCharacter(at:)`. Each property delegates to `base`.
- [ ] 3.3 Implement `insert(_:at:)`, `delete(in:)`, `replace(range:with:)` on `TransferableUndoable` using the auto-group pattern: open group if not grouping, delegate to base, record operation, close group if auto-opened.
- [ ] 3.4 Implement `undoGrouping(actionName:_:)` on `TransferableUndoable` — call `log.beginUndoGroup`, execute block, call `log.endUndoGroup(selectionAfter:)`. Support nested calls.
- [ ] 3.5 Implement `undo()` and `redo()` on `TransferableUndoable` — delegate to `log.undo(on: base)` and `log.redo(on: base)`, then restore the returned `selectionBefore` / `selectionAfter` onto `base.selectedRange`. Add `canUndo` and `canRedo` computed properties.
- [ ] 3.6 Create `Tests/TextBufferTests/TransferableUndoableTests.swift` — unit tests: insert/delete/replace produce undoable operations; undo restores content + selection; redo restores content + selection; undo→redo is identity; `undoGrouping` groups multiple ops; nested `undoGrouping` works. All using `MutableStringBuffer` as `Base`.

## 4. Equivalence Drift Tests (TASK-006)

- [ ] 4.1 Unguard `assertUndoEquivalence` in `AssertUndoEquivalence.swift` — implement the full step-dispatch loop using static dispatch for each `BufferStep` case on both `Undoable<MutableStringBuffer>` and `TransferableUndoable<MutableStringBuffer>`. Handle `.group` recursively via `undoGrouping`.
- [ ] 4.2 Create `Tests/TextBufferTests/UndoEquivalenceDriftTests.swift` — write equivalence tests for: simple insert/undo/redo; delete; replace; grouped operations; interleaved edits and undos; multiple undos then new edit (redo tail truncation); selection state at every step across all scenarios. All tests must pass.

## 5. AppKit Bridge (TASK-007)

- [ ] 5.1 Create `Sources/TextBuffer/Buffer/PuppetUndoManager.swift` — implement `@MainActor public final class PuppetUndoManager: NSUndoManager` with `weak var owner: (any PuppetUndoManagerDelegate)?`. Set `groupsByEvent = false` in `init`.
- [ ] 5.2 Implement `PuppetUndoManagerDelegate` as an internal `@MainActor` protocol on `TransferableUndoable` with: `puppetUndo()`, `puppetRedo()`, `puppetCanUndo: Bool`, `puppetCanRedo: Bool`, `puppetUndoActionName: String`, `puppetRedoActionName: String`.
- [ ] 5.3 Override `undo()`, `redo()`, `canUndo`, `canRedo`, `undoActionName`, `redoActionName` in `PuppetUndoManager` to delegate to `owner` (returning safe defaults when `owner` is `nil`).
- [ ] 5.4 Override all `registerUndo` variants in `PuppetUndoManager` as no-ops.
- [ ] 5.5 Implement `enableSystemUndoIntegration()` on `TransferableUndoable` — lazily create and store a `PuppetUndoManager(owner: self)`, return it as `NSUndoManager`. Repeated calls return the same instance.
- [ ] 5.6 Make `TransferableUndoable` conform to `PuppetUndoManagerDelegate` — wire `puppetUndo()` → `self.undo()`, `puppetCanUndo` → `log.canUndo`, etc.
- [ ] 5.7 Create `Tests/TextBufferTests/PuppetUndoManagerTests.swift` — tests: `canUndo`/`canRedo` reflect log state; `undoActionName`/`redoActionName` reflect log; `puppet.undo()` triggers log undo; `puppet.redo()` triggers log redo; `registerUndo` call is silently ignored; queries after owner deallocation return safe defaults; repeated `enableSystemUndoIntegration()` returns same instance.

## 6. Transfer API (TASK-008, TASK-009)

- [ ] 6.1 Add `snapshot()` to `TransferableUndoable` — create `MutableStringBuffer(wrapping: base)`, wrap in `TransferableUndoable<MutableStringBuffer>`, assign `result.log = self.log` (value copy). Return the copy.
- [ ] 6.2 Add `represent(_:)` to `TransferableUndoable` — `precondition(!log.isGrouping)`, replace base content via `base.replace(range: base.range, with: source.content)`, set `base.selectedRange = source.selectedRange`, assign `self.log = source.log` (value copy). Do not record this as an undoable operation.
- [ ] 6.3 Create `Tests/TextBufferTests/TransferAPITests.swift` — unit tests: `snapshot()` produces independent copy; mutating copy doesn't affect original; mutating original doesn't affect copy; `represent()` replaces content, selection, and log; `represent()` + `undo()` restores source's previous state; `represent()` + `undo()` + `redo()` restores source's state; `represent()` with open group crashes.
- [ ] 6.4 Unguard the three integration tests in `TransferIntegrationTests.swift` (Test A, B, C). Add two additional cases: snapshot during active puppet bridge; `represent()` discards receiver's previous undo state. Verify all five tests pass.
