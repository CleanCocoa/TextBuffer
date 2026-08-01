## Context

The M2 gap-closure fold (`0.8.2..0.9.0`) landed 40 commits, of which ten changed rope behavior and two added public API. The release notes for 0.9.0 disclose two of them: the insert-unwind CRLF seam repair (`8b1f7da`) and the composed-sequence read expansion (`9570025`). Everything else was compressed into one `Changed` bullet about invariant verification.

The compression is understandable — most of the fold *is* test work, and the structural fixes were framed at the time as "closing known structural debt" rather than as user-visible changes. But every one of the seven changes the tree shape a document ends up in: chunk sizes, split points, and merge outcomes all differ from 0.8.2. Anything a downstream consumer built on observed leaf layout (nothing in this repo, but `TheArchive2` snapshots rope state) sees different output for identical inputs.

DEF-012's docs half is a smaller, self-contained inconsistency: the `[M3 Rope Queries]` markers were added by `0955d7d` to two of the three materializing call sites, and the third — the default `lineRange` that `SendableRopeBuffer` inherits — was missed.

## Goals / Non-Goals

**Goals:**
- Every public API addition and behavior-changing fix from the 0.9.0 fold named in `CHANGELOG.md`, in the repo's existing entry style.
- All three full-document-materializing text-analysis call sites carry the same `[M3 Rope Queries]` marker.
- The `RopeBuffer` DocC header's large-document recommendation scoped to the operations that actually honor it.

**Non-Goals:**
- Making `lineRange`/`wordRange` O(log n) — M3 Rope Queries.
- Removing any `[M3 Rope Queries]` marker.
- Rewriting the released `## 0.9.0` / `## 0.9.1` sections (open question 1 in the proposal).
- Any test, source-behavior, or API change.

## Decisions

### 1. CHANGELOG entry style follows the existing prose convention

The repo's entries are full sentences describing observable behavior and its consequence, not commit subjects. Compare 0.9.0's CRLF entry ("The insert unwind now repairs the seam by redistributing the two boundary chunks through the grapheme-safe balanced split point, for sibling leaves and across subtree boundaries alike — the guarantee the delete path already enforced.") against its commit subject ("fix(rope): repair CRLF seams on the insert unwind"). Each of the seven new `Fixed` entries states what used to happen, what happens now, and why it matters to a reader who never opens the source.

Symbols are backticked; `TextRope`, `RopeBuffer`, and `SendableRopeBuffer` lead the entry where the change is buffer-visible.

### 2. Seven entries, not one rolled-up bullet

Rolling the fixes into "chunk invariants are now enforced" is what created DEF-013. Construction, insert, split, leaf merge, inner merge, and the delete seam are separate failure modes with separate observable consequences, so they get separate entries. They are ordered by pipeline position (construction → insert → split → merge → delete seam), which is also roughly their commit order.

### 3. The `[M3 Rope Queries]` marker is copied, not paraphrased

`TextAnalysisCapable.swift:46` already has the canonical wording. The new marker on `lineRange` reuses it verbatim except for the method name and the inheritor it names (`SendableRopeBuffer` rather than "rope-backed buffers"), so a future `grep '\[M3 Rope Queries\]'` sweep finds three uniform sites.

### 4. The DocC caveat is scoped, not hedged

`RopeBuffer`'s header keeps its recommendation — the rope genuinely is the better choice for large-document editing — but names the operations it applies to (insert, delete, replace) and states the exception (`lineRange(for:)`/`wordRange(for:)` materialize the full document per call). A vague "performance may vary" hedge would be worse than the current overclaim: it would remove the actionable fact.

### 5. A `MODIFIED` spec delta rather than `skip_specs: true`

The template permits `skip_specs: true` for pure docs changes, but every archived change in this repo carries a delta, and the caveat is a normative statement about the public documentation's content — the kind of externally observable contract specs are for. The delta restates the existing `RopeBuffer conforms to TextAnalysisCapable` requirement with its two existing scenarios intact and adds one scenario for the documented caveat, so promoting it on archive is a clean superset.

## Risks / Trade-offs

- **[Retroactive `[Unreleased]` entries read as new work]** A reader of the next release notes will see seven `Fixed` entries for changes that shipped one or two releases ago. Mitigated by a lead-in noting they landed in the 0.9.0 fold and are disclosed retroactively; the alternative (amending 0.9.0 in place) rewrites published history and is left as an open question.
- **[Under-disclosure persists]** The seven commits DEF-013 enumerates are not the complete set of behavior-changing fixes in the fold — the two `findLeaf` fixes are also undisclosed (proposal open question 2). Fixing only the enumerated seven closes DEF-013 as written while leaving a smaller gap.
- **[The caveat becomes stale when M3 lands]** The DocC caveat and the third `[M3 Rope Queries]` marker must be removed together with the other two when the summary-guided traversal ships. Mitigated by the uniform marker text: one grep finds all three sites and the spec scenario that pins the caveat.

## Resolved open questions (2026-08-01)

1. **Placement: amend the released `## 0.9.0` section in place** — historical accuracy wins over append-only. The `[Unreleased]`-retro-block assumption in tasks.md is superseded; the CHANGELOG tasks rework at apply time to target the 0.9.0 section directly (no retro lead-in needed — entries sit where the release sits).
2. **`findLeaf` fixes stay undisclosed**: internal API, unreachable by any 0.8.2 caller.
3. **The 0.9.0 `Changed` bullet stands** once the `Fixed` entries land beside it in the same section.
4. **DocC scope**: as tasked; the verified-only sites (task 4.3) stay unedited.
5. **DEFECTS.md bookkeeping** is release-side work done in this repo by this workflow, not part of the change's tasks.
6. **Scope addition**: fill in the eleven `## Purpose / TBD` headers on the promoted canonical specs (`openspec/specs/*/spec.md:3-4`) — one-paragraph purposes derived from each capability's requirements.
