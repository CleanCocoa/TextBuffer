## Why

Two disclosure defects from the 2026-07-29 review of the M2 gap-closure fold (`0.8.2..0.9.0`) are open against 0.9.1:

- **DEF-013 — CHANGELOG 0.9.0 gaps.** The 0.9.0 section has no `Added` section at all, so two public API additions shipped undisclosed: `RopeBuffer: CustomStringConvertible` (`98b5a35`) and the public composed-sequence surface on `TextRope` (`9570025`, named only in passing inside a `Fixed` entry). Seven behavior-changing structural fixes to construction, insert, split, delete, and merge are collapsed into a single `Changed` bullet that reads as test/verification work ("M2 rope verification complete: structural invariants … are enforced by the tree validator"). A reader cannot tell that chunk layout, split points, and merge outcomes actually changed — which they did, for any document large enough to span leaves.
- **DEF-012 (docs half) — `lineRange`/`wordRange` O(n) vs. the public large-document claim.** `RopeBuffer.swift:44` and `TextAnalysisCapable.swift:46` carry `[M3 Rope Queries]` markers for the full-document materialization, but the default `lineRange` at `TextAnalysisCapable.swift:51-55` — the overload `SendableRopeBuffer` inherits, i.e. the one `InMemoryBuffer` users hit — is untagged, and the `RopeBuffer` DocC header still claims it is "a better choice than `MutableStringBuffer` when working with very large documents" with no caveat. The claim is true for insert/delete/replace and false for text analysis.

Both are documentation debt only. Fixing them costs nothing at runtime and removes a claim the library cannot currently honor.

## What Changes

**CHANGELOG catch-up (DEF-013), all under a new `## [Unreleased]` section:**

- `Added`: `RopeBuffer: CustomStringConvertible` — guillemet/caret selection notation matching `MutableStringBuffer` and the `TextBufferTesting` helpers.
- `Added`: the public composed-sequence API on `TextRope` — `composedCharacterSequences(in:)` and `composedCharacterSequence(at:)`, window-materializing equivalents of `NSString.rangeOfComposedCharacterSequences(for:)` / `rangeOfComposedCharacterSequence(at:)`.
- `Fixed`: seven entries disclosing the structural fixes folded into 0.9.0 — `b0da6b5` (construction tail chunks/groups), `dd1c866` (root-leaf insert re-chunking), `e5345b4` (n-way inner split), `3ecbe42` (midpoint leaf split point), `8e7ec0c` (leaf merge redistribution and leftward absorption), `2abfd52` (inner-node merge redistribution and upward undersize propagation), `5cce7ae` (delete rejoining a CRLF pair split across well-sized leaves).

**Source documentation (DEF-012, docs half):**

- Add the missing `[M3 Rope Queries]` marker to the default `lineRange(for:)` in `TextAnalysisCapable.swift:51-55`, mirroring the wording already on the sibling `wordRange(for:)` at `:46` and naming `SendableRopeBuffer` as the inheritor.
- Soften the `RopeBuffer` DocC header (`RopeBuffer.swift:4-7`): scope the large-document recommendation to insert/delete/replace and state that `lineRange(for:)`/`wordRange(for:)` currently materialize the full document on every call.

## Capabilities

### New Capabilities
_(none)_

### Modified Capabilities
- `rope-buffer-conformance`: the "RopeBuffer conforms to TextAnalysisCapable" requirement gains the documented performance caveat — the text-analysis operations materialize the full document per call, and the public documentation must disclose that instead of claiming unqualified large-document superiority.

**Why a spec delta at all:** this change is documentation-only and would normally qualify for `skip_specs: true`. Every archived change in this repo carries a `specs/` delta, and the caveat being added is an externally visible, normative statement about what the public documentation must say — not an implementation note. So a single minimal `MODIFIED` requirement is included rather than a skip marker. No behavior of the code changes; the delta re-states the existing requirement verbatim plus one new scenario.

## Impact

- **Modified file:** `CHANGELOG.md` — new `## [Unreleased]` section with `### Added` (2 entries) and `### Fixed` (7 entries). Existing released sections are left untouched.
- **Modified file:** `Sources/TextBuffer/Buffer/TextAnalysisCapable.swift` — one comment added in the default `lineRange(for:)` body.
- **Modified file:** `Sources/TextBuffer/Buffer/RopeBuffer.swift` — DocC header caveat.
- **Modified file:** `DEFECTS.md` — DEF-013 status, and a note on DEF-012 that its docs half is addressed while the O(log n) implementation remains M3.
- **No source behavior changes.** No new tests: there is nothing observable to assert. The repo's TDD convention (red test first) does not apply to any task in this change — every task is a prose edit. Verification is `swift build` (the `TextAnalysisCapable` comment sits inside an `@inlinable` body) plus the existing green suite.
- **API:** none.

## Out of Scope (Non-Goals)

- **The actual O(log n) `lineRange`/`wordRange` implementation** — summary-guided rope traversal replacing `self.content as NSString`. That is M3 Rope Queries scope and is exactly what the `[M3 Rope Queries]` markers track. This change documents the current cost; it does not reduce it.
- Removing the `[M3 Rope Queries]` markers — they stay until M3 lands.
- Any of the remaining open defects (DEF-001 through DEF-011, DEF-014). The seven fixes are only *described* here, not revisited.
- Amending the released `## 0.9.0` and `## 0.9.1` sections in place (see open questions).

## Open Questions

1. **Retroactive disclosure placement.** All new entries go under `## [Unreleased]`, per the instruction and the repo's keepachangelog convention — but the seven fixes and both API additions actually shipped in 0.9.0. Options: (a) leave 0.9.0 untouched and let `[Unreleased]` carry the disclosure, with each entry noting the fixes landed in the 0.9.0 fold; (b) amend the `## 0.9.0` section in place, which is historically accurate but rewrites a published release. Tasks assume (a) with a short lead-in; confirm before implementing.
2. **Three more undisclosed fixes in the same fold.** `ea9531c` (`findLeaf` skipped past the last child at end-of-document offsets) and `1053d4b` (`findLeaf` preconditions out-of-range offsets) are behavior-changing fixes in `0.8.2..0.9.0` that DEF-013 does not enumerate and the CHANGELOG does not mention. `8b1f7da` (insert-unwind CRLF seam repair) *is* already disclosed. Should the two `findLeaf` fixes be folded into this catch-up, or left for a DEF-013 follow-up?
3. **Does the `Changed` bullet in 0.9.0 need a correction?** It is not wrong, but read alone it implies the fold was verification work. If option (a) above is chosen, the bullet stays as-is and the new `Fixed` entries supply the missing half.
4. **Scope of the DocC softening.** DEF-012 names only `RopeBuffer.swift:6-7`. `ChoosingABuffer.md:30` ("O(log n) insert, delete, and replace, even for large documents") and `TextRope.swift:4` are already scoped to mutations and appear accurate — a task verifies this rather than edits them. Confirm no caveat is wanted on `SendableRopeBuffer`'s DocC header too, given it inherits the untagged default `lineRange` and is the `InMemoryBuffer` typealias.
5. **DEFECTS.md bookkeeping.** Should a docs change flip DEF-013 to `fixed` and annotate DEF-012 as half-addressed, or is DEFECTS.md maintained only at release time?
