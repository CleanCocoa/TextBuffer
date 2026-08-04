## Why

ADR-012 makes every *split point* fall on a `Character` boundary — but a grapheme cluster can come to span a leaf seam without any split point ever being wrong, by **adjacency change**: a mutation puts new content at a leaf edge, or removes the content that separated two leaves, and the characters now adjacent across the seam combine into one cluster. Seam repair today handles exactly one such cluster, `\r\n`: the `crlfSeam(between:)` predicate (`Sources/TextRope/Node+Merge.swift:2-10`) byte-matches a trailing `\r` against a leading `\n`, and both the insert descent's post-splice check (`TextRope+Insert.swift:48`) and the delete path's merge gate and merge loops (`TextRope+Delete.swift:87,95-103`, `Node+Merge.swift:31,76`) consult only it. This is DEF-016 (DEFECTS.md, Medium), with two verified repros (2026-08-04, flagged by the test-side `leafSeamViolations` validator; the suite is otherwise green):

1. **Insert**: `TextRope(String(repeating: "a", count: 4096))`, then `insert("\u{301}", at: 2048)`. The splice lands at leaf-local offset 0 of the right leaf; the overflow re-chunk yields leaves `[2048, 1025, 1025]`; no edge chunk is undersized so `redistributeStarvedEdge` (`TextRope+Insert.swift:85-99`) skips, and the seam check at `:48` covers only `crlfSeam`. The cluster `a\u{301}` spans the seam after leaf 0.
2. **Delete**: `TextRope("a"×2048 + "b\u{301}" + "c"×2045)`, then `delete(in: 2048..<2049)` removes the base `b`, leaving the right leaf starting with `\u{301}` adjacent to leaf 0's trailing `a`. The delete path's seam handling is CRLF-only and the right leaf (2047 bytes) is not undersized, so nothing fires.

Both violate `openspec/specs/rope-core-types/spec.md`'s "Split points never fall inside a grapheme cluster" scenario ("no grapheme cluster SHALL span a chunk seam"). Reads stay code-unit-faithful — `content(in:)` slices by UTF-16 offsets and concatenation preserves counts, so no wrong content is observable and DEF-009's window-length precondition never fires — but the broken thing is the structural invariant that precondition's hard-failure justification, and ADR-012's reasoning generally, rest on.

The root cause is conceptual, and the fix follows from it: `\r\n` is one Swift `Character`, so the existing CRLF seam machinery is a *special case* of the general grapheme-seam repair. Generalizing the predicate turns the machinery that already exists — `repairCRLFSeam`'s recombine-through-`rebalancedChunks`, the merge loops' seam-driven combination — into the complete fix.

Coverage gap, addressed alongside: the stress alphabet (`Tests/TextRopeTests/TextRopeStressTests.swift:559-567`) contains no lone grapheme extenders, so no random operation can place a combining mark at a leaf boundary and the per-operation-validated seed (DEF-007, seed `0xDEF007`) never saw the shape.

## What Changes

- **`crlfSeam(between:)` generalizes to `graphemeSeam(between:)`** (`Sources/TextRope/Node+Merge.swift`): take the left subtree's last `Character` and the right subtree's first `Character`; a seam violation exists iff their concatenation forms fewer than two `Character`s under Swift stdlib grapheme breaking. The predicate stays stdlib-only (the TextRope target is Foundation-free per ADR-013) and stays in agreement with the test-side `leafSeamViolations` validator, the same producer/validator pairing `Node.isBoundaryStarved` has for starvation. CRLF remains the named special case, matched by the general rule instead of by byte comparison.
- **The repair machinery is reused, not rebuilt.** `repairCRLFSeam` (`TextRope+Insert.swift:104-134`) already recombines the two seam leaves through `Node.rebalancedChunks` and splices overflow siblings; it is renamed `repairGraphemeSeam` and driven by the generalized predicate. The delete path's `mergeUndersizedLeaves` / `mergeUndersizedInnerNodes` loops and the `deleteFromInner` merge gate switch from `crlfSeam` to `graphemeSeam` at their existing call sites.
- **Seam checks run unconditionally at every mutation-touched adjacency**, never gated on undersized chunks: the insert descent's post-splice check at `TextRope+Insert.swift:48` (already unconditional; only its predicate was too narrow) and the delete path's rejoin gate at `TextRope+Delete.swift:87` (`hasCRLFSeam` → `hasGraphemeSeam`, keeping the gate's or-term so the merge runs even when nothing is undersized and nothing was removed).
- **A repair may legally produce ADR-012's starved shapes**: `rebalancedChunks` on the combined seam content can yield a whole-cluster oversized leaf or a minimal-shortfall starved split. Those outcomes are legal per ADR-012's bounds and the specs say so — the seam invariant is absolute, the byte bounds are not.
- **Boundary semantics stated explicitly**: the seam invariant is Swift-grapheme-based (`Character`, per ADR-012), NOT NSString-composed-sequence-based. The NSString parity machinery lives in TextBuffer per ADR-013's 2026-08-03 amendment and is unaffected by this change.
- **Stress alphabet gains grapheme extenders** — a lone combining mark (`\u{301}`), ZWJ (`\u{200D}`), and variation selector (`\u{FE0F}`) — so the per-operation-validated seed exercises adjacency-formed clusters. The oracle comparison implications (Swift `String ==` uses canonical equivalence; combining marks make byte-level fidelity checkable only via code-unit comparison) are handled in the stress-testing tasks.
  > [2026-08-04, implementation] The extender alphabet exposed the distinct pre-existing DEF-017 (delete-merge starvation ignores the other-side neighbor) on all five pinned seeds — reproduced byte-identically on pre-change sources. The alphabet extension therefore moves to DEF-017's fix change (tasks 5.1/5.3 notes); the byte-exact oracle comparison landed here. DEF-016's class stays pinned by `GraphemeSeamRepairTests`.
- **The two DEF-016 repros land as red-first regression tests** asserted through `leafSeamViolations`, before any producer change.

Out of scope, by construction: **construction** (`chunkLeaves` splits at `Character` boundaries and never changes adjacency — it cannot create these seams) and **replace** (composes delete + insert, so it is fixed when they are).

No public API changes. Every touched symbol is `internal` or `private`; content, counts, and all read results are unchanged — the fix only changes where leaf boundaries fall.

## Capabilities

### New Capabilities
<!-- None — this change corrects existing capabilities. -->

### Modified Capabilities
- `rope-core-types`: the no-cluster-spans-a-seam invariant is restated to hold after **every mutation** — adjacency changes included — not only at split-point selection; the two DEF-016 adjacency shapes become scenarios
- `rope-insert`: the CRLF seam-repair requirement generalizes to grapheme seams (CRLF as the named special case), with the post-splice adjacency check unconditional and the ADR-012 starved outcomes of a repair stated as legal
- `rope-delete`: the CRLF rejoin behavior in undersized-leaf merging generalizes likewise — a seam-spanning cluster exposed by deletion triggers rejoin regardless of chunk sizes
- `rope-stress-testing`: the mixed-encoding alphabet requirement gains lone grapheme-extender operands so random operations can form clusters across adjacencies

## Impact

- **Modified source:** `Sources/TextRope/Node+Merge.swift` (`crlfSeam` → `graphemeSeam`, merge-loop call sites), `Sources/TextRope/TextRope+Insert.swift` (seam-check call site, `repairCRLFSeam` → `repairGraphemeSeam`), `Sources/TextRope/TextRope+Delete.swift` (`hasCRLFSeam` → `hasGraphemeSeam` gate)
- **New test file:** `Tests/TextRopeTests/GraphemeSeamRepairTests.swift` — the two DEF-016 repros plus adjacency-repair property tests (`NodeSplitPointTests.swift` stays the DEF-001 split-point suite; adjacency repair is a distinct mechanism)
- **Modified tests:** `Tests/TextRopeTests/TextRopeStressTests.swift` (extender alphabet entries; oracle-comparison note), `Tests/TextRopeTests/TreeInvariantValidation.swift` only if predicate-agreement coverage needs a new case (the `leafSeamViolations` validator itself is already correct and MUST NOT be weakened)
- **Defects closed:** DEF-016 (Medium)
- **Behavior change:** leaf-boundary placement only. Content, counts, and every public API result are unchanged; repairs choose among partitions of the same string.
- **Not addressed here:** DEF-011's read-path performance (a generalized seam predicate adds `Character`-level work per touched adjacency, bounded by cluster length — noted in design.md risks); NSString composed-sequence parity (TextBuffer's, per ADR-013 amendment); any construction or replace change (structurally unaffected, see above).
