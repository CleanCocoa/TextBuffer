## Why

Two disclosure defects from the 2026-07-29 review of the M2 gap-closure fold (`0.8.2..0.9.0`) are open against 0.9.1:

- **DEF-013 — CHANGELOG 0.9.0 gaps.** The 0.9.0 section has no `Added` section at all, so two public API additions shipped undisclosed: `RopeBuffer: CustomStringConvertible` (`98b5a35`) and the public composed-sequence surface on `TextRope` (`9570025`, named only in passing inside a `Fixed` entry). Seven behavior-changing structural fixes to construction, insert, split, delete, and merge are collapsed into a single `Changed` bullet that reads as test/verification work ("M2 rope verification complete: structural invariants … are enforced by the tree validator"). A reader cannot tell that chunk layout, split points, and merge outcomes actually changed — which they did, for any document large enough to span leaves.
- **DEF-012 (docs half) — `lineRange`/`wordRange` O(n) vs. the public large-document claim.** `RopeBuffer.swift:44` and `TextAnalysisCapable.swift:46` carry `[M3 Rope Queries]` markers for the full-document materialization, but the default `lineRange` at `TextAnalysisCapable.swift:51-55` — the overload `SendableRopeBuffer` inherits, i.e. the one `InMemoryBuffer` users hit — is untagged, and the `RopeBuffer` DocC header still claims it is "a better choice than `MutableStringBuffer` when working with very large documents" with no caveat. The claim is true for insert/delete/replace and false for text analysis.

Both are documentation debt only. Fixing them costs nothing at runtime and removes a claim the library cannot currently honor.

## What Changes

**CHANGELOG catch-up (DEF-013), amending the released `## 0.9.0` section in place** (decision 2026-08-01: historical accuracy over append-only — the entries describe what 0.9.0 actually shipped, so they belong in 0.9.0's section; a retroactive `[Unreleased]` block was considered and rejected). No retro lead-in is needed: the entries sit where the release sits. The existing 0.9.0 `Changed` bullet ("M2 rope verification complete …") stands unmodified beside the new entries — it supplies the verification half, the new `Fixed` entries the behavior half. The two `findLeaf` fixes in the same fold (`ea9531c`, `1053d4b`) stay undisclosed: internal API, unreachable by any 0.8.2 caller.

- `Added`: `RopeBuffer: CustomStringConvertible` — guillemet/caret selection notation matching `MutableStringBuffer` and the `TextBufferTesting` helpers.
- `Added`: the public composed-sequence API on `TextRope` — `composedCharacterSequences(in:)` and `composedCharacterSequence(at:)`, window-materializing equivalents of `NSString.rangeOfComposedCharacterSequences(for:)` / `rangeOfComposedCharacterSequence(at:)`.
- `Fixed`: seven entries disclosing the structural fixes folded into 0.9.0 — `b0da6b5` (construction tail chunks/groups), `dd1c866` (root-leaf insert re-chunking), `e5345b4` (n-way inner split), `3ecbe42` (midpoint leaf split point), `8e7ec0c` (leaf merge redistribution and leftward absorption), `2abfd52` (inner-node merge redistribution and upward undersize propagation), `5cce7ae` (delete rejoining a CRLF pair split across well-sized leaves).

**Source documentation (DEF-012, docs half):**

- Add the missing `[M3 Rope Queries]` marker to the default `lineRange(for:)` in `TextAnalysisCapable.swift:51-55`, mirroring the wording already on the sibling `wordRange(for:)` at `:46` and naming `SendableRopeBuffer` as the inheritor.
- Soften the `RopeBuffer` DocC header (`RopeBuffer.swift:4-7`): scope the large-document recommendation to insert/delete/replace and state that `lineRange(for:)`/`wordRange(for:)` currently materialize the full document on every call.

**Canonical spec Purpose fill-ins (scope added 2026-08-01):**

Eleven canonical specs under `openspec/specs/` still carry the archive-time placeholder `## Purpose` / `TBD - created by archiving change <name>. Update Purpose after archive.` (lines 3-4 of each). This change fills each in with a one-paragraph purpose derived from that capability's requirements: `rope-buffer-conformance`, `rope-buffer-drift`, `rope-core-types`, `rope-delete`, `rope-edge-cases`, `rope-insert`, `rope-replace`, `rope-stress-testing`, `rope-target-setup`, `rope-transfer-convergence`, `rope-utf16-navigation`.

*Mechanism:* canonical specs normally change only by archive-promoting a change's `specs/` delta, but deltas operate on `### Requirement:` blocks — a Purpose header is non-normative prose with no delta representation (the repo's spec rules in `openspec/config.yaml` govern requirements and scenarios only). So the fill-ins are direct edits to `openspec/specs/*/spec.md`, performed at apply time as tasks of this change; no requirement or scenario text changes, so archive promotion is unaffected.

## Capabilities

### New Capabilities
_(none)_

### Modified Capabilities
- `rope-buffer-conformance`: the "RopeBuffer conforms to TextAnalysisCapable" requirement gains the documented performance caveat — the text-analysis operations materialize the full document per call, and the public documentation must disclose that instead of claiming unqualified large-document superiority.

**Why a spec delta at all:** this change is documentation-only and would normally qualify for `skip_specs: true`. Every archived change in this repo carries a `specs/` delta, and the caveat being added is an externally visible, normative statement about what the public documentation must say — not an implementation note. So a single minimal `MODIFIED` requirement is included rather than a skip marker. No behavior of the code changes; the delta re-states the existing requirement verbatim plus one new scenario.

## Impact

- **Modified file:** `CHANGELOG.md` — the released `## 0.9.0` section gains a `### Added` subsection (2 entries) and seven entries appended to its existing `### Fixed` list; its `Changed` bullet stands. `## 0.9.1` and everything older are left untouched.
- **Modified file:** `Sources/TextBuffer/Buffer/TextAnalysisCapable.swift` — one comment added in the default `lineRange(for:)` body.
- **Modified file:** `Sources/TextBuffer/Buffer/RopeBuffer.swift` — DocC header caveat.
- **Modified files:** the eleven `openspec/specs/*/spec.md` listed above — placeholder `## Purpose` paragraph replaced; requirements and scenarios untouched.
- **No source behavior changes.** No new tests: there is nothing observable to assert. The repo's TDD convention (red test first) does not apply to any task in this change — every task is a prose edit. Verification is `swift build` (the `TextAnalysisCapable` comment sits inside an `@inlinable` body) plus the existing green suite.
- **API:** none.

## Out of Scope (Non-Goals)

- **The actual O(log n) `lineRange`/`wordRange` implementation** — summary-guided rope traversal replacing `self.content as NSString`. That is M3 Rope Queries scope and is exactly what the `[M3 Rope Queries]` markers track. This change documents the current cost; it does not reduce it.
- Removing the `[M3 Rope Queries]` markers — they stay until M3 lands.
- Any of the remaining open defects (DEF-001 through DEF-011, DEF-014). The seven fixes are only *described* here, not revisited.
- The `## 0.9.1` section and everything older than 0.9.0 — only the `## 0.9.0` section is amended.
- Disclosing the two `findLeaf` fixes (`ea9531c` end-of-document child skip, `1053d4b` out-of-range offset preconditions). Resolved 2026-08-01: internal API, unreachable by any 0.8.2 caller — they stay undisclosed, deliberately.
- `DEFECTS.md` bookkeeping (flipping DEF-013 to `fixed`, annotating DEF-012's docs half). Resolved 2026-08-01: that is release-side work done by the release workflow, not a task of this change.

## Resolved Questions (2026-08-01)

The proposal's five open questions were resolved in the 2026-08-01 grilling (recorded in `design.md` "Resolved open questions" and `DEFECTS.md` "Decisions"); the sections above reflect them:

1. **Placement** — amend the released `## 0.9.0` section in place; historical accuracy over append-only. The `[Unreleased]` retro-block (with lead-in) is rejected; no lead-in is needed since the entries sit where the release sits.
2. **`findLeaf` fixes** — stay undisclosed (internal API, unreachable at 0.8.2).
3. **The 0.9.0 `Changed` bullet** — stands as-is once the `Fixed` entries land beside it in the same section.
4. **DocC softening scope** — as tasked; the verified-only sites stay unedited.
5. **DEFECTS.md bookkeeping** — release-side work, not part of this change's tasks.
