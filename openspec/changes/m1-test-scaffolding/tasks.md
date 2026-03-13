## 1. BufferStep Enum (TASK-001a)

- [x] 1.1 Create `Sources/TextBufferTesting/BufferStep.swift` with public enum `BufferStep` containing cases: `insert(content: String, at: Int)`, `delete(range: NSRange)`, `replace(range: NSRange, with: String)`, `select(NSRange)`, `undo`, `redo`, `group(actionName: String?, steps: [BufferStep])`
- [x] 1.2 Verify `swift build` succeeds with the new file

## 2. assertUndoEquivalence Scaffolding (TASK-001b)

- [x] 2.1 Create `Sources/TextBufferTesting/AssertUndoEquivalence.swift` with the `assertUndoEquivalence(reference:subject:steps:file:line:)` function signature and body wrapped in `#if false`
- [x] 2.2 Add the convenience wrapper `assertUndoEquivalence(initial:steps:file:line:)` that creates both buffers from an initial string, also guarded with `#if false`
- [x] 2.3 Add a private helper `applyStep(_:to:)` within the guard that applies a single `BufferStep` to any `Buffer & Undoable`-like type via static dispatch (insert/delete/replace/select/undo/redo/group)
- [x] 2.4 Verify `swift build` succeeds — the guarded code is not compiled but the file is syntactically present

## 3. Transfer Integration Tests (TASK-002)

- [x] 3.1 Create `Tests/TextBufferTests/TransferIntegrationTests.swift` with class `TransferIntegrationTests: XCTestCase`
- [x] 3.2 Add guarded (`#if false`) test method `testTransferOutPreservesUndo` — Test A: editor inserts twice → snapshot → undo on copy → verify content equals state after first insert
- [x] 3.3 Add guarded (`#if false`) test method `testTransferInPreservesUndo` — Test B: in-memory buffer with changes → represent in editor → undo → verify content equals source's previous state
- [x] 3.4 Add guarded (`#if false`) test method `testTransitivity` — Test C: in-memory → represent → snapshot → all three undo/redo identically
- [x] 3.5 Verify `swift test` passes with no new failures (guarded tests are not compiled)

## 4. Final Verification

- [x] 4.1 Run `swift build` and confirm zero errors
- [x] 4.2 Run `swift test` and confirm all existing tests still pass
- [x] 4.3 Verify all three new files exist: `BufferStep.swift`, `AssertUndoEquivalence.swift`, `TransferIntegrationTests.swift`
