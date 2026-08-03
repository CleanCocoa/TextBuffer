## 1. Rebase Gate (this change lands last in the 0.10.0 train)

- [x] 1.1 Verify `fix-rope-split-point`, `fix-composed-sequence-reads`, `fix-rope-cow-and-equality-coverage`, `perf-rope-equality-and-bulk-insert`, and `docs-rope-disclosure` are archived. Re-diff every delta under `specs/` against the now-canonical specs: requirement headers must match exactly (notably `rope-utf16-navigation`'s "Composed character sequence reads match full-document NSString semantics" added by `fix-composed-sequence-reads`), and MODIFIED texts must carry forward any wording those archives changed. Adjust deltas before writing code.
- [x] 1.2 Re-run the Foundation survey and reconcile with design.md's table: `grep -rn "NSRange\|NSString\|import Foundation" Sources/TextRope/`. Expect exactly the four API files plus doc references — plus whatever `fix-composed-sequence-reads` added inside `TextRope+ComposedSequences.swift` (RI anchor walk, window cap). Any *other* hit means an unplanned Foundation dependency landed mid-train; stop and extend the plan before proceeding.
- [x] 1.3 Run the full `swift test` suite and record it green as the migration baseline.

## 2. Red: `Range<Int>` Primitives on TextRope (tests first)

- [x] 2.1 Add `Range<Int>`-form tests to `Tests/TextRopeTests/TextRopeNavigationTests.swift`: `content(in: 5..<11)` mirrors of the existing NSRange cases, empty in-bounds range (`3..<3` returns `""`), full-document range, and out-of-bounds trap expectations in `TextRopeNavigationPreconditionTests.swift` (negative `lowerBound`, `upperBound > utf16Count`, and the DEF-004 empty-range-out-of-bounds trap `500..<500`). These fail to compile — that is the red state.
- [x] 2.2 Implement `content(in: Range<Int>) -> String` in `TextRope+Navigation.swift` as the primary implementation (move the body; keep precondition messages equivalent). Re-point the existing `content(in: NSRange)` to forward to it. 2.1 tests green; whole suite green — the entire legacy NSRange suite now exercises the new primitive.
- [x] 2.3 Add `Range<Int>`-form delete tests to `TextRopeDeleteTests.swift` (representative mirrors: single-leaf, spanning, empty range no-op `3..<3`, surrogate-pair edges, trap cases). Red (compile failure).
- [x] 2.4 Implement `delete(in: Range<Int>)` in `TextRope+Delete.swift` as the primary; NSRange method forwards. Green.
- [x] 2.5 Add `Range<Int>`-form replace tests to `TextRopeReplaceTests.swift`, including the degenerate observable-equivalence cases as specced by the DEF-006b amendment: empty-string replace result equals `delete(in:)` alone; empty-range replace result equals `insert(_:at:)` alone; both-empty is a no-op. Red.
- [x] 2.6 Implement `replace(range: Range<Int>, with: String)` in `TextRope+Replace.swift` as the primary (delete + insert composition unchanged); NSRange method forwards. Green.
- [x] 2.7 Add tests for the new `utf16CodeUnits(in: Range<Int>) -> [UTF16.CodeUnit]` primitive: equality with `Array(content.utf16)[range]` on mixed-encoding content, a range splitting a surrogate pair returns the raw halves (this is the property `content(in:)` cannot provide), empty range, full range, multi-leaf spanning range, bounds traps. Red.
- [x] 2.8 Implement `utf16CodeUnits(in:)` in `TextRope+Navigation.swift` as `package func` (not `public` — resolved 2026-08-03), via the same tree walk as `content(in:)` (O(log n + k), no `Character`-boundary assumptions). Green.

## 3. Move TextBuffer Call Sites to the Primitives

- [x] 3.1 `Sources/TextBuffer/Buffer/RopeBuffer.swift`: convert every internal `rope.` call that passes an NSRange to the `Range<Int>` form (`content(in:)`, `delete(in:)`, `replace(range:with:)`) — the public `Buffer` API keeps NSRange, conversion happens at the call site after the existing `contains(range:)` guards.
- [x] 3.2 `Sources/TextBuffer/Buffer/SendableRopeBuffer.swift`: same conversion, including the `undo()`/`redo()` operation-replay paths (`:173-199`) that construct ranges from logged operations.
- [x] 3.3 Full `swift test` green — `RopeBufferDriftTests`, conformance, transfer, and undo suites unchanged and passing is the proof of unchanged buffer behavior.

## 4. Relocate Composed-Sequence Machinery to the TextBuffer Target

- [x] 4.1 `git mv Sources/TextRope/TextRope+ComposedSequences.swift Sources/TextBuffer/TextRope+ComposedSequences.swift`. Keep the public NSRange signatures and precondition behavior identical; adapt internals: window materialization through `content(in: Range<Int>)`, trail-surrogate detection through `utf16CodeUnits(in:)` (single-unit read), and the RI-run anchor walk through backward block reads of `utf16CodeUnits(in:)` (fixed block size, no per-code-unit tree descent — preserve the `fix-composed-sequence-reads` D2 mitigation), keeping the 4096-unit cap and full-document fallback.
- [x] 4.2 `git mv Tests/TextRopeTests/TextRopeComposedSequencesTests.swift Tests/TextBufferTests/TextRopeComposedSequencesTests.swift`; change its import to `TextBuffer`. Assertions unchanged.
- [x] 4.3 Full `swift test` green. The moved composed tests, the RI drift sweeps, and the CRLF-containing drift cases are the fidelity oracle for the re-plumbed leaf access; any divergence here is a bug in 4.1, not a test to update.

## 5. Remove NSRange from TextRope; Add the Convenience Layer (single slice — no state may declare both)

- [x] 5.1 Rewrite the remaining NSRange usages in `TextRopeTests` to `Range<Int>` form: `TextRopeNavigationTests` (10), `TextRopeNavigationPreconditionTests` (1), `TextRopeDeleteTests` (36), `TextRopeReplaceTests` (20), `TextRopeStressTests` (25). Mechanical `NSRange(location: l, length: n)` ⇢ `l..<l+n`; expected values untouched. Remove every `import Foundation` from `Tests/TextRopeTests/`. Suite green (both APIs still exist at this point).
- [x] 5.2 Delete the NSRange-taking methods and `import Foundation` from `TextRope+Navigation.swift`, `TextRope+Delete.swift`, `TextRope+Replace.swift`, and in the same commit add `Sources/TextBuffer/TextRope+NSRange.swift`: `@inlinable @inline(__always)` extensions on `TextRope` with the removed signatures — `content(in: NSRange)`, `delete(in: NSRange)`, `replace(range: NSRange, with:)` — each validating `location != NSNotFound`, `location >= 0`, `length >= 0` (trap messages equivalent to the removed ones) and forwarding `location ..< location + length` to the primitive.
- [x] 5.3 Add `Tests/TextBufferTests/TextRopeNSRangeParityTests.swift`: for representative ropes (ASCII, multi-byte, emoji, multi-leaf), each wrapper's result/mutation equals the `Range<Int>` primitive's; trap tests for `NSNotFound` location, negative location, negative length on all three wrappers. Thin parity only — behavior depth stays in `TextRopeTests`.
- [x] 5.4 Update `TextRope.swift`'s type doc comment and `Sources/TextRope/Documentation.docc/Documentation.md` (`delete(in: NSRange(...))` / `replace(range: NSRange(...))` examples ⇢ `Range<Int>` forms; note that NSRange conveniences come with TextBuffer). Mention the NSRange layer in TextBuffer's DocC where the rope backend is introduced.
- [x] 5.5 Verification gate: `grep -rn "NSRange\|NSString\|import Foundation" Sources/TextRope/` returns nothing; `swift build` and full `swift test` green; `swift test --filter TextRopeTests` builds with the test target free of Foundation imports (the `rope-target-setup` scenario made checkable).

## 6. Spec Truth and Bookkeeping

- [ ] 6.1 Confirm the `specs/` deltas in this change match what shipped (post-1.1 rebase, post-implementation): `rope-target-setup` Foundation-free requirement + NSRange-convenience requirement, `rope-utf16-navigation` `Range<Int>` restatement + `utf16CodeUnits(in:)` + composed-read re-homing, `rope-replace` DEF-006b observable wording, `rope-delete` / `rope-edge-cases` / `rope-stress-testing` restatements.
- [ ] 6.2 Update `DEFECTS.md`: mark DEF-006 bullets (a) NSRange contradiction and (b) replace degenerate clauses as `fixed`, naming `foundation-free-textrope`; leave the Node+Merge and Purpose-TBD bullets to their owning changes' entries.
- [ ] 6.3 Add the CHANGELOG entry under the 0.10.0 release notes: a `### Changed`/breaking note — TextRope's public range API is now `Range<Int>` over UTF-16 code units; NSRange forms moved to TextBuffer-target extensions (consumers importing TextBuffer are unaffected); composed-sequence APIs now provided by the TextBuffer target; TextRope no longer imports Foundation.
- [ ] 6.4 Run `openspec validate foundation-free-textrope --strict` and the full `swift test` suite one final time before archiving.
