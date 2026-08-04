## Why

Both `TextRope` mutation primitives early-return on an empty operand *before* their bounds preconditions, so out-of-bounds mutations with an empty operand silently succeed instead of trapping:

- `Sources/TextRope/TextRope+Delete.swift:6`: `if utf16Range.isEmpty { return }` precedes both preconditions, so `TextRope("hello").delete(in: 500..<500)` silently succeeds. This violates the canonical `openspec/specs/rope-delete/spec.md` "Out-of-bounds range traps" scenario — `upperBound > utf16Count` MUST trap, and an empty range at 500 has `upperBound == 500`.
- `Sources/TextRope/TextRope+Insert.swift:4`: `if string.isEmpty { return }` precedes the offset precondition, so `TextRope("hello").insert("", at: 500)` silently succeeds. The insert spec states the offset "MUST be in the range `0...utf16Count`" but has no trap scenario, so the hole is a spec gap as well as a behavior bug.

The `NSRange` delete wrapper (`Sources/TextBuffer/TextRope+NSRange.swift:28-33`) validates only the `NSRange`-specific degenerate encodings (`NSNotFound`, negative location or length) and forwards `location ..< location + length` to the primitive, which by its own doc comment "owns the bounds checks against `utf16Count`" — so `delete(in: NSRange(location: 500, length: 0))` silently succeeds too. `replace(range:with:)` is unaffected: its own preconditions run before composing the primitives.

This is DEF-015, the mutation-side sibling of DEF-004, which was fixed in 0.10.0 by `fix-composed-sequence-reads` for the read APIs only. That change recorded the governing decision — bounds preconditions move *before* the empty-range early returns; in-bounds empty operations keep their no-op behavior — and this change applies the identical decision to `delete(in:)` and `insert(_:at:)`.

## What Changes

- **Out-of-bounds trap for empty delete ranges** — the two bounds preconditions in `delete(in:)` (`Sources/TextRope/TextRope+Delete.swift`) move *before* the `utf16Range.isEmpty` early return, so an empty range at an out-of-bounds location traps instead of silently succeeding. An in-bounds empty range (`0 <= k <= utf16Count` for `k..<k`) remains a no-op — the early return still runs before `ensureUnique()`, so no tree mutation or path copy occurs.
- **Out-of-bounds trap for empty-string inserts** — the offset precondition in `insert(_:at:)` (`Sources/TextRope/TextRope+Insert.swift`) moves *before* the `string.isEmpty` early return, so `insert("", at:)` with an offset outside `0...utf16Count` traps. Inserting an empty string at an in-bounds offset remains a no-op.
- **NSRange delete wrapper inherits the fix** — `Sources/TextBuffer/TextRope+NSRange.swift` needs no source change: the wrapper forwards to the primitive, whose bounds checks now run for zero-length ranges too, so `delete(in: NSRange(location: 500, length: 0))` traps. Covered by a wrapper-level exit test.
- **Regression tests, red first** — process-exit tests (`await #expect(processExitsWith: .failure)`) for the empty out-of-bounds delete at the rope level (`Range<Int>` form) and at the TextBuffer `NSRange` wrapper level, and for `insert("", at: outOfBounds)`; plus green tests pinning that in-bounds empty deletes and empty-string inserts stay no-ops.
- **Spec deltas closing the gap** — the rope-delete "Out-of-bounds range traps" requirement gains an explicit empty-range trap scenario and its empty-range no-op scenario states the in-bounds condition; the rope-insert requirement gains its missing "Out-of-bounds offset traps" scenario (covering non-empty and empty strings) and its empty-string no-op scenario states the in-bounds condition.
- **Disclosure** — the behavior tightening (empty-operand out-of-bounds mutations now trap instead of silently succeeding) is recorded in `CHANGELOG.md` under `## [Unreleased]`.

No public API shape changes; the only behavior change is the trap where a silent no-op previously masked an out-of-bounds argument.

## Capabilities

### New Capabilities
<!-- None — this change corrects and tightens existing capabilities. -->

### Modified Capabilities
- `rope-delete`: the "Delete a UTF-16 range" requirement states that bounds validation precedes the empty-range early return — an empty out-of-bounds range traps (new scenario), and the empty-range no-op scenario is conditioned on the range being in bounds
- `rope-insert`: the "Insert at UTF-16 offset" requirement states that offset validation precedes the empty-string early return — an out-of-bounds offset traps for non-empty and empty strings alike (new scenario, previously absent entirely), and the empty-string no-op scenario is conditioned on the offset being in bounds

## Impact

- **Sequencing:** none — no dependency on other open changes; `fix-composed-sequence-reads` (whose decision this applies) is implemented and archived.
- **Modified source:** `Sources/TextRope/TextRope+Delete.swift` and `Sources/TextRope/TextRope+Insert.swift` — one statement reordered in each. `Sources/TextBuffer/TextRope+NSRange.swift` is deliberately untouched; the wrapper inherits the fix through forwarding.
- **Modified test files:** `Tests/TextRopeTests/TextRopeDeleteTests.swift` (extends the existing `TextRopeDeleteIntRangePreconditions` exit-test suite), `Tests/TextRopeTests/TextRopeInsertTests.swift` (gains its first exit-test suite), `Tests/TextBufferTests/TextRopeNSRangeParityTests.swift` (wrapper-level empty out-of-bounds delete). TextRopeTests is Foundation-free — all `NSRange` tests stay in TextBufferTests.
- **Defects closed:** DEF-015 (medium).
- **Behavior change:** `delete(in:)` with an empty out-of-bounds range, `insert("", at:)` with an out-of-bounds offset, and the `NSRange` delete wrapper with a zero-length out-of-bounds location now trap instead of silently succeeding. In-bounds empty operations remain no-ops. Buffer layer unaffected: `RopeBuffer` and `SendableRopeBuffer` validate ranges via `contains(range:)` and throw before reaching the rope, exactly as with DEF-004. `replace(range:with:)` unaffected — its own preconditions already run first.
- **Not addressed here:** DEF-016 (grapheme-cluster leaf seams from insert/delete adjacency) — a separate structural defect in the same files, tracked independently.
