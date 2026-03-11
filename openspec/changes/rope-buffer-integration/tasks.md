## 1. RopeBuffer Implementation (TASK-019)

- [ ] 1.1 Create `Sources/TextBuffer/Buffer/RopeBuffer.swift` — declare `final class RopeBuffer: Buffer, TextAnalysisCapable` with `var rope: TextRope` and `var selectedRange: NSRange`; add `@MainActor` isolation and `typealias` declarations
- [ ] 1.2 Implement `init(_ content: String = "")` — construct `TextRope(content)`, set `selectedRange` to zero range
- [ ] 1.3 Implement read-only `Buffer` accessors: `var content: String`, `var range: NSRange`, `func content(in:)`, `func unsafeCharacter(at:)`
- [ ] 1.4 Implement `insert(_:at:)` — delegate to `rope.insert`, then apply MutableStringBuffer-identical selection-shift rule (insert before/at selection start shifts right by UTF-16 length of inserted string)
- [ ] 1.5 Implement `delete(in:)` — delegate to `rope.delete`, then apply MutableStringBuffer-identical selection-clamp rule (overlap → shrink; swallow → collapse to deletion start; after → no change)
- [ ] 1.6 Implement `replace(range:with:)` — delegate to `rope.replace`, then apply delete-then-insert selection adjustment in sequence
- [ ] 1.7 Implement `modifying(affectedRange:_:)` — follow `MutableStringBuffer` exactly: validate that `affectedRange` is within `range`, then execute the block with no additional selection-adjustment side effects.
- [ ] 1.8 Declare `TextAnalysisCapable` conformance and rely on the existing default implementations for `wordRange(for:)` and `lineRange(for:)`, which operate via `content` because `RopeBuffer` has `Range == NSRange` and `Content == String`.

## 2. RopeBuffer Unit Tests (TASK-019)

- [ ] 2.1 Create `Tests/TextBufferTests/RopeBufferTests.swift` — test empty init, string init, `content`, `range`, `utf16Count`
- [ ] 2.2 Test `content(in:)` — correct substring for ASCII, multi-byte, emoji; throws `BufferAccessFailure` for out-of-range
- [ ] 2.3 Test `insert` selection adjustment — insert before cursor shifts right; insert at cursor with range selection shifts location; insert after cursor no change
- [ ] 2.4 Test `delete` selection adjustment — delete before cursor shifts left; overlap shrinks selection; swallow collapses; after cursor no change
- [ ] 2.5 Test `replace` selection adjustment — replace shorter shifts left for selections after; replace longer shifts right; replace overlapping selection collapses to replacement end
- [ ] 2.6 Test `unsafeCharacter(at:)` — ASCII, multi-byte boundary
- [ ] 2.7 Test empty-buffer edge cases — insert into empty, delete on empty-after-delete, replace whole content

## 3. RopeBuffer Drift Tests (TASK-020)

- [ ] 3.1 Create `Tests/TextBufferTests/RopeBufferDriftTests.swift` — write `makeEquivalentPair(initial:)` helper that returns a `(RopeBuffer, MutableStringBuffer)` pair with identical initial content and selection
- [ ] 3.2 Port "insert before selection" scenario from `BufferBehaviorDriftTests` — assert `content` and `selectedRange` match after each step
- [ ] 3.3 Port "insert at selection" scenario (cursor insert, range-selection insert)
- [ ] 3.4 Port "insert after selection" scenario
- [ ] 3.5 Port "delete before selection" scenario
- [ ] 3.6 Port "delete overlapping selection" and "delete swallowing selection" scenarios
- [ ] 3.7 Port "replace shorter" and "replace longer" scenarios
- [ ] 3.8 Port "sequential insert/delete interleaved" scenario (multiple operations, assert after each)
- [ ] 3.9 Add large-document random-operation scenario — generate 500+ random insert/delete/replace operations via `SystemRandomNumberGenerator`, apply identically to both buffer types, assert no mismatch at any step

## 4. TransferableUndoable<RopeBuffer> Convergence Tests (TASK-021)

- [ ] 4.1 Create `Tests/TextBufferTests/RopeTransferIntegrationTests.swift`
- [ ] 4.2 Test undo/redo on `TransferableUndoable<RopeBuffer>` directly — single insert undoable; grouped operations undo as one step; undo then redo is identity; redo tail truncated after new edit post-undo
- [ ] 4.3 Test `snapshot()` from rope-backed buffer — snapshot content and selection match source; `undo()` on snapshot restores to pre-edit state; source is unaffected by mutations on snapshot
- [ ] 4.4 Test `represent()` loading string-backed state into rope-backed buffer — content replaced; selection replaced; after `represent(source)`, `undo()` on the rope-backed buffer produces the same content and selection states that `undo()` on the source would have produced at the moment of representation.
- [ ] 4.5 Test `represent()` precondition — assert `preconditionFailure` when called with an open undo group (use `XCTAssertPreconditionFailure` or equivalent guard)
- [ ] 4.6 Implement transfer-out transitivity test (Test A from TASK-009 rope variant) — rope buffer edited twice, `snapshot()` taken, `undo()` on snapshot produces first-edit content
- [ ] 4.7 Implement transfer-in transitivity test (Test B rope variant) — string buffer edited twice, `represent()` into rope buffer, `undo()` on rope buffer produces first-edit content
- [ ] 4.8 Implement full transitivity test (Test C rope variant) — string → `represent()` into rope → `snapshot()` → `undo()` on all three produces identical content
- [ ] 4.9 Implement a dedicated cross-type transferable-undo equivalence helper using static dispatch — run the same `BufferStep` sequence on `TransferableUndoable<RopeBuffer>` (subject) and `TransferableUndoable<MutableStringBuffer>` (reference); verify content and selection match at every step including `.undo`, `.redo`, and `.group` steps. Do not assume the existing `assertUndoEquivalence` helper is generic over arbitrary buffer bases.
- [ ] 4.10 Run `swift test` — all tests in `RopeBufferTests`, `RopeBufferDriftTests`, and `RopeTransferIntegrationTests` pass with no regressions in existing suites
