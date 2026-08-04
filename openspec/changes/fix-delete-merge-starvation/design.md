## Context

ADR-012 (grapheme-first chunk bounds) legalizes an undersized leaf only under **per-adjacent-leaf** starvation: for *each* adjacent leaf, the combination must exceed `maxChunkUTF8` and hold no `Character` boundary in its legal window. The test-side validator encodes exactly that — and defines adjacency **cross-parent**: `chunkSizeViolations(in:)` (`Tests/TextRopeTests/TreeInvariantValidation.swift:67-87`) flattens the whole tree via `collectLeaves(root)` and judges every undersized leaf against `leaves[index - 1]` and `leaves[index + 1]` in document order, with no regard for parent nodes. The producer must be held to that same definition (D1).

The delete-path merge falls short on one side. Anatomy of `mergeUndersizedLeaves` (`Sources/TextRope/Node+Merge.swift:33-63`), which runs per inner node whose leaves a delete touched:

| Step | Code | Other-side consultation? |
| --- | --- | --- |
| Undersized `current` mid-list | combines **rightward** via `combinedLeaf(current.chunk, next.chunk, ...)`; loop repeats while `current` stays undersized | Right side: yes, by the loop itself. |
| Undersized `current` at end of list | `merged.popLast()` and combines **leftward**; a fixed-point re-split is accepted without retry (the ADR-012 no-retry comment at `:49-52`) | Left side: yes, for the *returned* chunk. |
| Starved combination re-splits | `combinedLeaf` → `Node.rebalancedChunks` emits `chunks.dropLast()` **into `merged`** and returns the last chunk as the new `current` | **No.** A chunk pushed into `merged` is never re-examined. An undersized left output sits next to `merged.last` — the other-side neighbor — and nobody asks whether that pair could conform. |

That third row is DEF-017. In the repro (`[…, 1074, 1024, 1034, …]`, delete across the 1024|1034 seam → pair `[1023, 1027]`): the 2050-byte pair combination is starved (`U+1F389` spans the `[1024, 1026]` window), `rebalancedChunks` takes the minimal-shortfall split `[1023, 1027]`, the 1023 chunk lands in `merged` next to the 1074-byte leaf — whose 2097-byte combination has boundaries throughout its `[1024, 1073]` window — and the merge moves on. The validator rejects the shape; the producer never looked.

The insert path already solved its instance of this class: `redistributeStarvedEdge` (`Sources/TextRope/TextRope+Insert.swift:85-99`, commit `1e6a6aa`) consults the pre-existing neighbor of a carved edge chunk, gated by `Node.isBoundaryStarved` — the producer-side twin of the validator's `isStarvationJustified` (byte-for-byte the same window logic). That producer/validator pairing is the pattern to extend, not a new mechanism to invent.

**The cross-parent question.** Both `mergeUndersizedLeaves` and the insert path's `redistributeStarvedEdge` operate within one parent's `children` array, while the validator's adjacency is document-order across the whole tree. Within-parent repair alone therefore *cannot* honestly satisfy the validator: an undersized output at its parent's first/last position can have its conforming other-side neighbor under a sibling parent, and if the parent retains `>= minChildren` children, no upper-level merge fires today and the violation persists. The delete path does, however, already have a route to cross-parent leaf repair: `graphemeSeam(between:)` is evaluated between adjacent *subtrees* at every inner level of the deletion path (spine walks to the facing edge leaves), and when it fires, `combinedInner` concatenates the two subtrees' children under one node and re-runs the leaf merge — turning a cross-parent adjacency into a same-parent one. This change reuses that route (D3).

## Goals / Non-Goals

**Goals:**
- After any delete-path merge combination, an undersized output survives only when starved against **each** adjacent leaf in document order — producer matches the validator's predicate and its adjacency definition
- One shared starvation predicate (`Node.isBoundaryStarved`) at every new decision point — no second, drifting implementation
- Preserve the merge no-retry discipline: the new step is a single additional redistribution attempt, never a loop
- Land the deferred stress-alphabet extenders and get all five pinned seeds green over them (the change's acceptance criterion)

**Non-Goals:**
- No change to `rebalancedChunks`, `minimalShortfallSplitPoint`, or any split-point selection — the splits are correct; the omission is who gets consulted afterwards
- No change to the seam-repair machinery (`graphemeSeam` / `repairGraphemeSeam` are correct and stay as-is; only the gate/loop conditions gain a sibling predicate)
- No validator changes: `chunkSizeViolations` is already exact and MUST NOT be weakened to same-parent adjacency
- No insert-path rework beyond what the stress gate demands (see Risks — the insert path's own cross-parent residual has no known manifestation)
- No performance work; the new predicate is O(edge-leaf spine) at sites that already do O(chunk) work

## Decisions

### D1. Adjacency is document order over the flattened leaf sequence — the validator's definition wins

The load-bearing decision. Three candidate readings of ADR-012's "each adjacent sibling leaf": (a) same-parent siblings only, (b) document-order neighbors, (c) leave it ambiguous and fix only the observed repro. Decision: **(b)**, for three reasons:

1. **The validator has always checked (b).** `chunkSizeViolations` flattens the tree; `leaves[index ± 1]` crosses parent boundaries without noticing them. Choosing (a) would require *weakening the validator*, i.e. legalizing shapes it rejects today, purely to spare the producer work — inverting the producer/validator relationship that caught this defect in the first place.
2. **Leaf adjacency is a property of the document, not of the tree grouping.** Whether two adjacent leaves share a parent is an artifact of child batching; the starvation question — "could these bytes be repartitioned conformingly?" — is identical either way. The seam invariant already made this exact call: `leafSeamViolations` joins all leaves, and the producer meets it cross-parent via the seam predicate at every inner level.
3. **(c) is how DEF-001 became five manifestations.** Fixing the observed pair while leaving the definition unstated guarantees the next RNG reshuffle finds the edge case.

Consequence: the `rope-core-types` delta spells out that "adjacent sibling leaf" means adjacent in the flattened document-order leaf sequence, whether or not the leaves share a parent, and the producer must reach cross-parent adjacencies (D3). The mismatch between validator (cross-parent) and a same-parent-only fix is thereby resolved, not glossed.

### D2. Same-parent consultation: one leftward attempt at the emission site in `combinedLeaf`

When `combinedLeaf`'s `rebalancedChunks` output has an undersized **first** chunk and `merged` is non-empty, make a single redistribution attempt with `merged.last`:

- `combined = merged.last.chunk + chunks[0]`; if `Node.isBoundaryStarved(combined[...])` → accept the undersized chunk (it is now *provably* starved against both sides: the pair that produced it, and the other-side neighbor just tested). Emit as today.
- Otherwise → replace `merged.last` and `chunks[0]` with `Node.rebalancedChunks(in: combined[...])` output. `!isBoundaryStarved` guarantees the balanced two-way split exists with both chunks in `[minChunkUTF8, maxChunkUTF8]`, so the replacement cannot itself emit a new undersized chunk — the attempt cannot cascade (termination, D4).

Why this site and only this site:

- The **right**-edge output (`combinedLeaf`'s returned chunk) needs nothing new: if undersized, it remains `current` and the existing loop combines it rightward with the next child; at end of list, the existing `popLast` branch combines it leftward. Both sides get consulted by control flow that already exists.
- Chunks emitted into `merged` are the one blind spot — they exit the loop's field of view immediately. In the repro that is exactly the 1023 chunk.
- Consulting at emission time (inside/alongside `combinedLeaf`) rather than in a post-pass keeps the no-retry structure: each undersized emission gets at most one look leftward, and `merged` is never rescanned.

In the repro: `1023` + left neighbor `1074` → 2097, not starved → re-split at the window midpoint boundary → `[1049, 1048]`, then `current = 1027` appends; final `[1049, 1048, 1027]`, all conforming, `chunkSizeViolations` empty.

Implementation shape: `combinedLeaf` already takes `redistributingInto merged: inout ContiguousArray<Node>` — the consultation reads and rewrites `merged.last` through that same parameter; no signature change is forced (the exact factoring, e.g. a small `absorbLeftward(_:into:)` helper, is the implementer's choice).

### D3. Cross-parent consultation: an `absorbableStarvedEdge` predicate wired like the seam predicate

New predicate in `Node+Merge.swift`, mirroring `graphemeSeam(between:)`'s shape:

```
absorbableStarvedEdge(between left: Node, and right: Node) -> Bool
```

Walk to `left`'s rightmost leaf and `right`'s leftmost leaf (the same spine walks `graphemeSeam` does). Return `true` iff at least one of the two edge leaves is undersized (`chunk.utf8.count < Node.minChunkUTF8`) **and** their combined chunk is not `Node.isBoundaryStarved` — i.e. the cross-seam pair could conformingly absorb the shortfall. Wire it at the two places the seam predicate already sits:

1. **`deleteFromInner`'s merge gate** (`TextRope+Delete.swift:90`): a fourth or-term alongside `hasGraphemeSeam(node)` — scan adjacent child pairs with `absorbableStarvedEdge`. Without it, the gate never opens for the shape where nothing was removed and no *child of this node* reported undersize (the child parents absorbed the count change).
2. **`mergeUndersizedInnerNodes`' combine condition** (`Node+Merge.swift:86-87`): a disjunct next to `graphemeSeam(between: current, and: node.children[i])`, so the gate firing actually leads to `combinedInner(current, next)` for the specific pair. `combinedInner` concatenates the two nodes' children and recursively runs `mergeUndersizedChildren` — at the leaf level the pair is now same-parent and D2 repairs it; the `> maxChildren` mid-split afterwards regroups children without changing leaf adjacency, so it cannot undo the repair.

`mergeUndersizedLeaves`' own combine condition needs **no** new disjunct: an undersized leaf in a leaf-children array is already combined by the `current.chunk.utf8.count < Node.minChunkUTF8` term, and D2 covers its leftward blind spot.

**Completeness argument (why this reaches everything the validator checks).** Assume the invariant held before the operation (inductively true: the per-op-validated stress seed asserts it after every operation). A delete changes leaf sizes and adjacencies only along the deletion path. Any leaf pair adjacent in document order meets at their lowest common ancestor, which for any touched pair is an inner node on the deletion path — and `deleteFromInner` unwinds through every such node bottom-up, running the gate at each. A same-parent pair is handled at their direct parent (D2); a cross-parent pair is detected at the LCA by the gate's pair scan and funneled through `combinedInner` into the same-parent case. There is no third case, so producer and validator agree over the validator's own adjacency definition.

### D4. Termination and the no-retry discipline

The existing discipline — a provably starved leaf is a fixed point; merge scans accept it without re-attempting (`Node+Merge.swift:49-52`, spec'd in rope-delete's "Merges do not retry") — is preserved by construction:

- **D2 terminates**: at most one leftward attempt per emitted chunk, and a successful attempt emits only conforming chunks (`!isBoundaryStarved` ⇒ the balanced split exists), so it cannot trigger another attempt. A failed attempt changes nothing and is not repeated — the failure *is* the starvation proof for that side. The outer loop still advances `i` monotonically.
- **D3 terminates**: after `combinedInner` runs, the specific edge pair is either conforming (repaired by D2 inside the recursive merge) or two-sided starved — in both cases `absorbableStarvedEdge` is `false` for it afterwards, so neither the gate nor the loop condition re-fires on the same shape. `mergeUndersizedInnerNodes` advances `i` per iteration as today, and `combinedInner`'s mid-split output satisfies `minChildren...maxChildren` on both halves, introducing no new undersize trigger.
- What changes semantically: "accepted as starved" now *means* starved against each adjacent leaf — the fixed point is only reachable after both sides have been consulted (the pair by the split that failed, the other side by the single D2/D3 attempt). Genuinely two-sided-starved shapes (e.g. the `[1023, 1026]` manifestation-3 pin, whose 1023 leaf has no other-side neighbor, and both-side-starved constructions) behave exactly as today: no oscillation, no repeated redistribution. The spec delta amends the no-retry paragraph to say the single consultation precedes fixed-point acceptance and does not constitute a retry.

### D5. Producer/validator agreement stays single-sourced

Every new decision uses `Node.isBoundaryStarved` — the same predicate `redistributeStarvedEdge` uses and the byte-for-byte twin of the validator's `isStarvationJustified`. No new window arithmetic is introduced anywhere; `absorbableStarvedEdge` is "undersized edge leaf ∧ ¬`isBoundaryStarved`(combined)" and nothing more. Doc comments at the new sites name the pairing, as `graphemeSeam` and `isBoundaryStarved` already do.

### D6. Stress-alphabet completion and the five-seed acceptance gate

Re-apply `fix-grapheme-seam-repair`'s reverted task 5.1: add `"\u{301}"`, `"\u{200D}"`, `"\u{FE0F}"` to `stressCharset` (`TextRopeStressTests.swift:559-577`) and delete the dated blocked-note comment that points at this change. Facts carried over from that change's 5.3/5.4 evidence, relied on here:

- With the extended alphabet on current main, all five pinned seeds fail with **only** this chunk-size class (zero seam violations) — so "all five seeds green over the extended alphabet" is a complete and honest acceptance criterion for this fix, and is red-first today without writing a new stress harness.
- The byte-exact oracle comparison (`Array(content.utf8) == Array(oracle.utf8)` in the per-op seed) already landed there and needs no change.
- The helpers were already reviewed under the extended alphabet: `validUTF16Offset` and `singleCharacters` need no change (each extender is one BMP scalar and passes the single-char filter intentionally); expectation-deriving tests derive from the oracle and stayed green. Tasks re-verify rather than re-derive.
- The dedicated per-op seed `0xDEF007` was observed *not* to produce an extender-at-boundary seam shape in its 2,000 ops — recorded then, still true now; the seam class is covered by the four 10k sampled seeds (which did produce persistent seam violations under pre-repair sources) plus `GraphemeSeamRepairTests`. This change does not force a generator change to manufacture the shape; it lands the alphabet whose absence was the recorded gap.

## Risks / Trade-offs

- **Insert-path cross-parent residual (stated, not glossed).** `redistributeStarvedEdge` on the insert path is also within-parent: a starved carved-edge chunk at its parent's boundary could in principle have a conforming neighbor under a sibling parent. No manifestation is known — the carved run's undersized-prone chunk is its residual-band edge, whose in-parent consultation covers the shapes observed to date — and the fix mechanism here is delete-path machinery (`deleteFromInner`'s gate), which insert does not traverse. Handling: the extended-alphabet five-seed gate is the empirical check; the tasks carry an explicit contingency — if a stress violation with an insert-path shape appears, stop, record it, and either extend the same edge consultation at the insert unwind sites within this change or file it as its own defect with evidence, exactly as `fix-grapheme-seam-repair` did for DEF-017 itself. What is *not* acceptable is reverting the alphabet again.
- **More merge work per delete.** The gate scans adjacent child pairs with spine walks (O(children × height) per touched inner node) and starved emissions pay one extra `isBoundaryStarved` window search. Both sit on paths already doing O(chunk) string splicing; `absorbableStarvedEdge` short-circuits on the cheap undersize test before any window search. Noted for DEF-011's ledger if profiles ever show it.
- **Tree-shape churn where violations used to sit.** Shapes change only where the validator rejects today's output (or where `combinedInner` regroups children legally). Content and counts are unchanged by construction; the full suite runs before any expectation is touched, and any changed expectation must be justified in task notes (the `fix-rope-split-point` discipline).
- **`combinedInner` funneling is heavier than a targeted edge repair.** Combining two inner nodes to fix one leaf pair concatenates and re-merges up to `2 × maxChildren` children. Accepted: it reuses code that already runs for seam-driven cross-parent combinations of exactly the same frequency class, and it cannot regress balance (output children counts stay within bounds). The lighter alternative is below.

## Alternatives Considered

- **Same-parent fix only, documenting the cross-parent gap.** Rejected: the validator checks cross-parent adjacency, so this ships a known producer/validator mismatch — the dishonest resolution D1 exists to prevent. The gap is reachable (undersized output at a parent edge with a conforming neighbor beyond it), and the extended-alphabet seeds would be entitled to find it.
- **Weaken the validator to same-parent adjacency.** Rejected: legalizes shapes ADR-012's rationale does not justify (the bytes could be repartitioned conformingly; the parent boundary is a grouping artifact), and weakens the instrument that caught DEF-017. The validator is the contract; the producer moves.
- **Targeted spine-descending edge repair at ancestor levels** (a `repairGraphemeSeam`-style rewrite of the two facing edge leaves in place, instead of `combinedInner` funneling). Functionally equivalent and lighter per firing, but it duplicates repair plumbing that `combinedInner` → `mergeUndersizedLeaves` already provides on the delete path, adds a second write path into leaves under COW spine handling, and the seam machinery precedent (`fix-grapheme-seam-repair` D3) already chose loop-condition wiring for cross-subtree combination on this path. Revisit only if profiling flags the funneling.
- **Post-merge retry loop** (rescan `merged` until no absorbable undersized leaf remains). Rejected: violates the no-retry discipline the spec pins ("Merges do not retry"), reintroduces the oscillation risk that discipline exists to prevent, and is unnecessary — D2's single attempt provably cannot cascade.
- **Full-tree post-delete sweep** (run the validator's own flattened scan after every delete and repair findings). Correct but O(n) per delete; the LCA argument in D3 shows the touched adjacencies are exactly the ones the deletion path already visits. The validator keeps the whole-tree form as the independent check, where O(n) is fine.
- **Consult the other side before splitting the starved pair** (three-leaf combined redistribution: fold `merged.last` into the `rebalancedChunks` input). Attractive — one mechanism instead of split-then-repair — but it changes the split geometry for *every* starved combination (three-way outputs where today's shape is a spec'd two-way minimal-shortfall split), disturbing the pinned starved-band scenarios and `rebalancedChunks`' contract, for no additional coverage: split-then-single-consult reaches the same conforming end states. Rejected as the larger diff with equal power.
