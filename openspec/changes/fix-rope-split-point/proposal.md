## Why

`TextRope.Node.balancedSplitPoint` (`Sources/TextRope/Node+Split.swift:45-73`) searches its legal redistribution window `[low, high]` bidirectionally for a `Character` boundary — and then, when the window holds none, throws the window away: line 72 hands off to `splitPoint(in:targetUTF8:)`, which walks backward from the *midpoint* with no lower bound at all. The result is a split point outside the only range that can satisfy the chunk-size invariants. That single line is DEF-001, and it has four manifestations:

1. **Insert CRLF seam repair → oversized leaf** (deterministic, ASCII only). `repairCRLFSeam` (`TextRope+Insert.swift:70-88`) on a 4096-byte combination has a window of exactly one byte, and that byte is the CR/LF interior. Fallback yields `[2047, 2049]` — 2049 > `maxChunkUTF8`.
   ```swift
   let base = String(repeating: "a", count: 2047) + "\r" + String(repeating: "b", count: 2047)
   var rope = TextRope(base)          // leaves [2048, 2047]
   rope.insert("\n", at: 2048)        // leaves [2047, 2049]
   ```
2. **Delete CRLF rejoin of two 2048-byte leaves → the same `[2047, 2049]`, every time.** `TextRope+Delete.swift:131-141` → `combinedLeaf` (`:149-159`) reaches the identical window.
3. **Delete redistribution → undersized leaf that is a stable fixed point.** At `count == 2049` the window is two bytes wide; a 4-byte scalar straddling it yields `[1023, 1026]`, and re-running the merge reproduces the same split, so it never self-heals (observed persisting 300+ operations under fuzzing).
4. **`leafSplitPoint` (`Node+Split.swift:35-43`) has the same backward-only walk** and no window at all, so a scalar straddling the midpoint of an over-full leaf yields a 1022-byte chunk. `Tests/TextRopeTests/NodeTests.swift:42-48` pins the backward-only behavior for a neighbouring layout whose value, 1023, happens to be correct under the minimal-deviation rule — the right number for the wrong reason.

All four break `openspec/specs/rope-core-types/spec.md:114` ("each with chunk size between `minChunkUTF8` and `maxChunkUTF8` bytes"), `rope-insert/spec.md:53`, and `rope-delete/spec.md:68`. None is covered by a test: the stress suite validates tree invariants only every 100th operation (DEF-007, `TextRopeStressTests.swift:532,681`, `TextRopeInsertTests.swift:238`), and these states are transient enough to have slipped through 40,000 sampled operations.

The specs are also complicit. They state both chunk bounds as absolute, which is not achievable: when a single grapheme cluster straddles the entire legal window there is provably no split satisfying both bounds. ADR-012 (2026-08-01) settles which regime applies — **grapheme-first**: splits occur only at `Character` boundaries, the bounds MUST hold whenever a conforming boundary exists, and under provable boundary starvation the nearest-boundary minimal-deviation split (or a whole-cluster leaf) is taken. The specs must state that rule so the invariant checker can be tightened to run every operation without producing false failures.

## What Changes

- **One split-point site, window-aware.** `balancedSplitPoint` is replaced by `rebalancedChunks(in:)`, returning 1–3 chunks instead of a single index: a single chunk when `count <= maxChunkUTF8` (`== 2 * minChunkUTF8`, so any two-way split would undersize a side), the balanced two-way split when the window holds a `Character` boundary, and a **balanced three-way redistribution** when it does not (decided 2026-08-01: balanced everywhere, not the greedy left-heavy chunker — the fallback only fires on paths that are broken today, so no green test changes shape). `leafSplitPoint` and `TextRope+Construction.swift`'s `chunkEnd` are unified onto one `leadingChunkEnd(in:)` helper carrying the same window logic, so manifestation 4 and the latent construction-path twin are fixed at the same site.
- **Grapheme-first chunk bounds (ADR-012).** Split points fall on `Character` boundaries **only** — never inside a grapheme cluster, not even at a Unicode scalar boundary — which makes the `\r\n` never-split rule absolute instead of a special case. `[minChunkUTF8, maxChunkUTF8]` MUST hold whenever a conforming boundary exists. Under provable per-leaf **boundary starvation** the split with minimal deviation is taken: an undersized leaf is legal only when no adjacent sibling can absorb it and the combined slice has no boundary in its legal window; an oversized leaf is legal only as a single whole grapheme cluster larger than `maxChunkUTF8` (no fixed byte cap, no scalar-boundary escape hatch). The tree-invariant validator encodes exactly these predicates — exact, not a tolerance.
- **Merges do not retry.** A leaf out of bounds under proven starvation is a fixed point: subsequent merge scans accept it without re-attempting redistribution, so the shape neither oscillates nor re-runs the failed split.
- **Three-way plumbing at the two call sites.** `combinedLeaf` already appends spill-over leaves into the merge accumulator and needs only to append two. `repairCRLFSeam` currently rewrites two leaves in place; it gains a return value of overflow siblings that `insertIntoNode` splices after `children[i]`, reusing the sibling-insertion and `splitInner` path that already exists there (decided 2026-08-01: sibling return, no `buildTree` spine rebuild).
- **`Node+Merge.swift` extraction (DEF-006c).** The merge machinery (`mergeUndersizedChildren`, `mergeUndersizedLeaves`, `combinedLeaf`, `mergeUndersizedInnerNodes`, `combinedInner`) moves from `TextRope+Delete.swift` into the spec-named `Sources/TextRope/Node+Merge.swift`, symmetric with `Node+Split.swift` — pure file movement, disclosed here rather than by silent task edit.
- **DEF-001's four repros as regression tests**, red before the fix, plus property assertions (every leaf ≤ max or a single whole cluster; every leaf ≥ min or provably starved) rather than pinned magic numbers where the numbers are incidental.
- **DEF-007: a dedicated 2,000-operation stress seed validates tree invariants after every operation**, not every hundredth, so a transient invariant break fails at the operation that caused it. The four 10,000-operation seeds keep their 1% sampling.
- **DEF-014 test hygiene** for the items entangled with this fix: the pinned 1023 in `NodeTests` stays numerically but the test is renamed and reframed as the reasoned minimal-shortfall (boundary starvation) case per ADR-012, the two delete tests whose names claim merges they never execute, `testDeleteCausingLeafMerge`'s non-discriminating assertions (must pin `[1050, 1050]`), the `Node+Split.swift:71` doc comment that misstates the fallback's trigger, and the misplaced `MARK: - Delete` at `RopeBufferDriftTests.swift:49`.

No public API changes. `TextRope`'s surface is untouched; every symbol involved is `internal`.

## Capabilities

### New Capabilities
<!-- None — this change corrects existing capabilities. -->

### Modified Capabilities
- `rope-core-types`: chunk-size bounds restated per ADR-012 as grapheme-first (splits only at `Character` boundaries; bounds hold except under provable boundary starvation; minimal-deviation splits; whole-cluster oversized leaves legal), and construction's split-point selection specified as a window-clamped bidirectional search
- `rope-insert`: leaf splitting on overflow must respect the legal window in both directions and split only at `Character` boundaries; CRLF seam repair across adjacent leaves gains its own requirement, including the balanced three-way outcome
- `rope-delete`: undersized-leaf redistribution specified in terms of the window, the balanced three-way fallback, the minimal-deviation starved band, the single-leaf case, and merge no-retry
- `rope-stress-testing`: a dedicated 2,000-operation seeded run must validate tree invariants after every operation, judging out-of-bounds leaves against the exact starvation predicates

## Impact

- **Modified source:** `Sources/TextRope/Node+Split.swift` (rewritten split-point core), `Sources/TextRope/TextRope+Delete.swift` (`combinedLeaf` accepts 1–3 chunks; merge machinery then extracted), `Sources/TextRope/TextRope+Insert.swift` (`repairCRLFSeam` returns overflow siblings), `Sources/TextRope/TextRope+Construction.swift` (`chunkEnd` folded into `leadingChunkEnd`)
- **New source file:** `Sources/TextRope/Node+Merge.swift` — the merge machinery extracted from `TextRope+Delete.swift` (DEF-006c), pure movement
- **New test file:** `Tests/TextRopeTests/NodeSplitPointTests.swift` — the four DEF-001 repros plus window/boundary property tests
- **Modified tests:** `Tests/TextRopeTests/NodeTests.swift` (DEF-014, the pinned 1023 reframed), `Tests/TextRopeTests/TextRopeDeleteTests.swift` (DEF-014, merge-test naming and assertions), `Tests/TextRopeTests/TextRopeStressTests.swift` (DEF-007), `Tests/TextRopeTests/TextRopeInsertTests.swift` (DEF-007 sampling comment), `Tests/TextRopeTests/TreeInvariantValidation.swift` (exact starvation predicates), `Tests/TextBufferTests/RopeBufferDriftTests.swift` (DEF-014, misplaced MARK)
- **Defects closed:** DEF-001 (critical), DEF-007 (medium), DEF-006's `Node+Merge.swift` bullet (DEF-006c), DEF-014 except its `testConsecutiveRoundTripsAreIdempotent` bullet
- **Behavior change:** tree shape only. Content, counts, and every public API result are unchanged by construction — every rule is a choice among split points of the same string.
- **Not addressed here:** DEF-014's `RopeTransferIntegrationTests.swift:126-143` round-trip chaining (assigned to `fix-rope-cow-and-equality-coverage` per the 2026-08-01 triage); DEF-009's window-length desync, contained in `fix-composed-sequence-reads` — where, because ADR-012 guarantees chunk seams never fall mid-cluster, its defense graduates to a precondition; DEF-011's quadratic bulk insert, which touches `splitLeaf`'s caller but not its split point; DEF-006's remaining bullets (NSRange and the replace spec ride `foundation-free-textrope`; Purpose-TBD headers ride `docs-rope-disclosure`).

All formerly open questions were resolved on 2026-08-01 — see `design.md` → "Resolved open questions (2026-08-01, ADR-012)" and `docs/adr/adr-012--grapheme-first-chunk-bounds.md`.
