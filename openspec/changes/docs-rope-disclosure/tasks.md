> **No red-first sequencing.** Every task below is a prose edit to `CHANGELOG.md`, a doc comment, or a canonical spec's `## Purpose` header. Nothing changes observable behavior, so there is no failing test to write first; the repo's TDD convention does not apply. Verification is `swift build` + the existing green suite (group 6).

## 1. CHANGELOG — amend `## 0.9.0` in place

Decision 2026-08-01 (design.md "Resolved open questions", DEFECTS.md "Decisions"): the retro-disclosures amend the released `## 0.9.0` section in place — historical accuracy over append-only. Do **not** create a `## [Unreleased]` section and do **not** add a retroactive-disclosure lead-in; the entries sit where the release sits.

- [ ] 1.1 Insert a `### Added` subsection into `## 0.9.0`, above the existing `### Fixed` (matching the `Added` → `Fixed` ordering used in `## 0.8.0` and `## 0.5.0`).
- [ ] 1.2 Leave the existing `### Changed` bullet ("M2 rope verification complete …") exactly as-is — it stands beside the new `Fixed` entries, supplying the verification half while they supply the behavior half. Leave `## 0.9.1` and all older sections untouched.

## 2. CHANGELOG — `Added` entries under `## 0.9.0` (DEF-013, undisclosed public API)

- [ ] 2.1 `RopeBuffer: CustomStringConvertible` (`98b5a35`). Entry states: `RopeBuffer` now prints its selection state — `«guillemets»` around a selected range, `ˇ` at an insertion point — matching `MutableStringBuffer`, `SendableRopeBuffer`, and the `TextBufferTesting` notation, so drift-test failure output is readable for rope-backed buffers. Source: `Sources/TextBuffer/Buffer/RopeBuffer.swift:142-156`.
- [ ] 2.2 Public composed-sequence API on `TextRope` (`9570025`): `composedCharacterSequences(in:)` and `composedCharacterSequence(at:)`. Entry states: rope equivalents of `NSString.rangeOfComposedCharacterSequences(for:)` / `rangeOfComposedCharacterSequence(at:)` that expand a UTF-16 range or offset to composed character sequence boundaries, materializing only a window around the target (doubled whenever the expansion touches a window edge) rather than the whole document. The existing 0.9.0 `Fixed` entry names these only in passing; they are public API in their own right. Source: `Sources/TextRope/TextRope+ComposedSequences.swift:4-22`.

## 3. CHANGELOG — `Fixed` entries under `## 0.9.0` (DEF-013, seven structural fixes)

Append the seven entries to the existing `### Fixed` list under `## 0.9.0`, as a block ordered by pipeline position (construction → insert → split → merge → delete seam). Write each in the repo's existing prose style: full sentences, backticked symbols, what changed and why it is observable — not the commit subject. The two `findLeaf` fixes (`ea9531c`, `1053d4b`) are deliberately **not** disclosed (decision 2026-08-01: internal API, unreachable by any 0.8.2 caller) — do not add entries for them.

- [ ] 3.1 **Construction chunking** (`b0da6b5`). `TextRope` construction no longer emits an undersized tail chunk or an undersized tail group: the last two chunks are balanced when the remainder would fall below `minChunkUTF8`, and the cut steps back before a straddling `CR` instead of overflowing `maxChunkUTF8` past the `LF`. Tree grouping balances the last two groups the same way when the tail would fall below `minChildren`. Observable as a different leaf layout for the same input string.
- [ ] 3.2 **Root-leaf insert re-chunking** (`dd1c866`). A large insert into a single-leaf rope used to split once and promote an arbitrarily oversized remainder as the root's sibling. The root-leaf path now splices into the chunk and, on overflow, rebuilds through the construction chunk distribution, so every produced leaf lands within `minChunkUTF8...maxChunkUTF8` at any insert size.
- [ ] 3.3 **N-way inner-node split** (`e5345b4`). A single 50/50 split of an overflowing inner node could leave both halves still over `maxChildren` (56 children became 2×28). `splitInner` now distributes evenly into sibling groups of `minChildren...maxChildren`; the insert unwind splices all siblings into the parent, and the root path rebuilds through `buildTree` when the promoted sibling set itself overflows.
- [ ] 3.4 **Leaf split point moved to the midpoint** (`3ecbe42`). The leaf split point was a greedy cut at `maxChunkUTF8` on raw byte offsets, which could split extended grapheme clusters and overflowed the maximum by one byte to hop a straddling `CRLF`. It now targets the UTF-8 midpoint and snaps backward to the nearest grapheme-cluster boundary, so both halves stay at or above `minChunkUTF8` whenever the chunk is at least twice the minimum, neither half exceeds the maximum, and no `CRLF` pair or cluster is split. Construction's chunk end delegates to the same boundary-snapping split point.
- [ ] 3.5 **Leaf merge redistributes and absorbs leftward** (`8e7ec0c`). Delete's leaf merge stranded undersized leaves in three cases; all three are handled now — combined content over `maxChunkUTF8` is redistributed at a balanced split point so both leaves land in range, a trailing undersized leaf absorbs or redistributes leftward through its already-merged neighbor, and the balanced split point searches its window bidirectionally so grapheme-boundary adjustment cannot undershoot the minimum, keeping `CRLF` pairs and multi-byte characters intact.
- [ ] 3.6 **Inner-node merge mirrors the leaf pass** (`2abfd52`). Merging two inner nodes whose combined child count exceeds `maxChildren` now redistributes the children so both halves land in `minChildren...maxChildren`, a trailing undersized inner node absorbs or redistributes leftward, and the merge pass re-runs on the junction so an unfixable undersized child carried out of a single-child parent is absorbed by its new siblings — cascading level by level on the unwind. Delete from an inner node consumes the child-undersize signal instead of discarding it.
- [ ] 3.7 **Delete rejoins a split `CRLF` pair** (`5cce7ae`). A delete that removed the text between a `\r` ending one leaf and a `\n` starting the next never triggered the merge pass when neither leaf went undersized, leaving the pair split across leaves in violation of the chunk invariant — including across subtree boundaries. The merge pass now also fires on a detected seam, and the leaf and inner merge loops absorb the seam pair, re-splitting at a grapheme-safe balanced point. This is the delete-side counterpart of the insert-unwind seam repair already listed in the same section.
- [ ] 3.8 Cross-check the finished section against the two entries already present under `## 0.9.0` (insert-unwind CRLF seam `8b1f7da`, composed-sequence read expansion `9570025`) — neither may be duplicated by the new entries. Re-read `## 0.9.1` and `## 0.8.x` for tone and confirm the new entries match (sentence prose, no commit hashes, no bullet-per-commit shorthand).

## 4. Source documentation (DEF-012, docs half)

- [ ] 4.1 `Sources/TextBuffer/Buffer/TextAnalysisCapable.swift` — add the missing `[M3 Rope Queries]` marker inside the default `lineRange(for:)` body (lines 51-55), immediately above the `return (self.content as NSString).lineRange(for: searchRange)`. Reuse the wording of the sibling marker on `wordRange(for:)` at line 46 verbatim, substituting the method name and naming `SendableRopeBuffer` as the inheritor of this overload. Three uniform sites must result: `RopeBuffer.swift:44`, `TextAnalysisCapable.swift:46`, and the new one.
- [ ] 4.2 `Sources/TextBuffer/Buffer/RopeBuffer.swift` lines 4-7 — scope the DocC claim. Keep the recommendation but name the operations it covers ("O(log n) insert, delete, and replace … a better choice than `MutableStringBuffer` for editing very large documents") and add a caveat sentence stating that `lineRange(for:)` and `wordRange(for:)` currently materialize the full document on every call, so text analysis is O(n) in document length. Do not use a vague hedge; the actionable fact is the point.
- [ ] 4.3 Verify — do not edit — the other large-document claims flagged during review: `Sources/TextRope/TextRope.swift:4`, `Sources/TextRope/Documentation.docc/Documentation.md:9`, `Sources/TextBuffer/Documentation.docc/ChoosingABuffer.md:12,30,53`, and `README.md:50`. Each appears already scoped to mutation cost, and per the 2026-08-01 decision ("DocC scope as tasked") these verified-only sites stay unedited. If any turns out to make an unscoped analysis claim, add it to this change's scope and note it in the proposal.
- [ ] 4.4 Decide whether `SendableRopeBuffer`'s DocC header needs the same caveat — it inherits the untagged default `lineRange` and is the `InMemoryBuffer` typealias, so it is the buffer most users hit. Apply or record the decision.

## 5. Canonical spec Purpose fill-ins (scope added 2026-08-01)

Replace the archive-time placeholder (`TBD - created by archiving change <name>. Update Purpose after archive.`, lines 3-4 of each file) with a one-paragraph purpose derived from that capability's `### Requirement:` blocks — what the capability guarantees and for whom, not how it is implemented. These are direct edits to the canonical specs: a `## Purpose` header is non-normative prose with no delta representation, so archive promotion does not cover it (mechanism noted in proposal.md). Requirements and scenarios stay byte-identical.

- [ ] 5.1 `openspec/specs/rope-target-setup/spec.md`
- [ ] 5.2 `openspec/specs/rope-core-types/spec.md`
- [ ] 5.3 `openspec/specs/rope-insert/spec.md`
- [ ] 5.4 `openspec/specs/rope-delete/spec.md`
- [ ] 5.5 `openspec/specs/rope-replace/spec.md`
- [ ] 5.6 `openspec/specs/rope-utf16-navigation/spec.md`
- [ ] 5.7 `openspec/specs/rope-buffer-conformance/spec.md`
- [ ] 5.8 `openspec/specs/rope-buffer-drift/spec.md`
- [ ] 5.9 `openspec/specs/rope-edge-cases/spec.md`
- [ ] 5.10 `openspec/specs/rope-stress-testing/spec.md`
- [ ] 5.11 `openspec/specs/rope-transfer-convergence/spec.md`
- [ ] 5.12 Confirm no `TBD` placeholder remains under `openspec/specs/` (`grep -rn "TBD" openspec/specs/` returns nothing).

## 6. Verification

- [ ] 6.1 `swift build` — the new marker in `TextAnalysisCapable.swift` sits inside an `@inlinable` body; confirm it compiles.
- [ ] 6.2 `swift test` — confirm the suite is still green. No test changes are expected; if any test asserts on doc-comment-adjacent behavior, that is a finding, not an edit.
- [ ] 6.3 `openspec validate docs-rope-disclosure --strict` — confirm the `MODIFIED` delta against `rope-buffer-conformance` resolves and the Purpose edits did not disturb any requirement.
