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
4. **`leafSplitPoint` (`Node+Split.swift:35-43`) has the same backward-only walk** and no window at all, so a scalar straddling the midpoint of an over-full leaf yields a 1022-byte chunk. `Tests/TextRopeTests/NodeTests.swift:42-48` currently pins that outcome as if it were correct.

All four break `openspec/specs/rope-core-types/spec.md:114` ("each with chunk size between `minChunkUTF8` and `maxChunkUTF8` bytes"), `rope-insert/spec.md:53`, and `rope-delete/spec.md:68`. None is covered by a test: the stress suite validates tree invariants only every 100th operation (DEF-007, `TextRopeStressTests.swift:532,681`, `TextRopeInsertTests.swift:238`), and these states are transient enough to have slipped through 40,000 sampled operations.

The specs are also complicit. They state both chunk bounds as absolute, which is not achievable: when a single grapheme cluster straddles the entire legal window there is provably no split satisfying both bounds. The fix therefore has to say which bound yields, and under exactly what condition — otherwise the invariant checker cannot be tightened to run every operation without producing false failures.

## What Changes

- **One split-point site, window-aware.** `balancedSplitPoint` is replaced by `rebalancedChunks(in:)`, returning 1–3 chunks instead of a single index: a single chunk when `count <= maxChunkUTF8` (`== 2 * minChunkUTF8`, so any two-way split would undersize a side), the balanced two-way split when the window holds a `Character` boundary, and a three-way split via the construction chunker when it does not. `leafSplitPoint` and `TextRope+Construction.swift`'s `chunkEnd` are unified onto one `leadingChunkEnd(in:)` helper carrying the same window logic, so manifestation 4 and the latent construction-path twin are fixed at the same site.
- **Bounds made honest and checkable.** `maxChunkUTF8` becomes a hard bound (exceedable only by ≤ 3 bytes, and only when no Unicode scalar boundary sits at the required offset — a >2048-byte grapheme cluster). `minChunkUTF8` becomes a best-effort bound with a precise, testable carve-out: a leaf may fall below it only when merging with each neighbour would exceed `maxChunkUTF8` *and* the combined slice has no `Character` boundary in its legal window. Both call sites and the invariant validator encode exactly that predicate.
- **Three-way plumbing at the two call sites.** `combinedLeaf` already appends spill-over leaves into the merge accumulator and needs only to append two. `repairCRLFSeam` currently rewrites two leaves in place; it gains a return value of overflow siblings that `insertIntoNode` splices after `children[i]`, reusing the sibling-insertion and `splitInner` path that already exists there.
- **DEF-001's four repros as regression tests**, red before the fix, plus property assertions (every leaf ≤ max; every leaf ≥ min or the carve-out predicate holds) rather than pinned magic numbers where the numbers are incidental.
- **DEF-007: one stress seed validates tree invariants after every operation**, not every hundredth, so a transient invariant break fails at the operation that caused it.
- **DEF-014 test hygiene** for the items entangled with this fix: the pinned 1023 in `NodeTests`, the two delete tests whose names claim merges they never execute, `testDeleteCausingLeafMerge`'s non-discriminating assertions (must pin `[1050, 1050]`), the `Node+Split.swift:71` doc comment that misstates the fallback's trigger, and the misplaced `MARK: - Delete` at `RopeBufferDriftTests.swift:49`.

No public API changes. `TextRope`'s surface is untouched; every symbol involved is `internal`.

## Capabilities

### New Capabilities
<!-- None — this change corrects existing capabilities. -->

### Modified Capabilities
- `rope-core-types`: chunk-size bounds restated as an asymmetric contract (hard max, best-effort min with an explicit carve-out predicate), and construction's split-point selection specified as a window-clamped bidirectional search
- `rope-insert`: leaf splitting on overflow must respect the legal window in both directions; CRLF seam repair across adjacent leaves gains its own requirement, including the three-way outcome
- `rope-delete`: undersized-leaf redistribution specified in terms of the window, the three-way fallback, and the single-leaf case
- `rope-stress-testing`: at least one seeded run must validate tree invariants after every operation

## Impact

- **Modified source:** `Sources/TextRope/Node+Split.swift` (rewritten split-point core), `Sources/TextRope/TextRope+Delete.swift` (`combinedLeaf` accepts 1–3 chunks), `Sources/TextRope/TextRope+Insert.swift` (`repairCRLFSeam` returns overflow siblings), `Sources/TextRope/TextRope+Construction.swift` (`chunkEnd` folded into `leadingChunkEnd`)
- **New test file:** `Tests/TextRopeTests/NodeSplitPointTests.swift` — the four DEF-001 repros plus window/boundary property tests
- **Modified tests:** `Tests/TextRopeTests/NodeTests.swift` (DEF-014, the pinned 1023), `Tests/TextRopeTests/TextRopeDeleteTests.swift` (DEF-014, merge-test naming and assertions), `Tests/TextRopeTests/TextRopeStressTests.swift` (DEF-007), `Tests/TextRopeTests/TextRopeInsertTests.swift` (DEF-007 sampling), `Tests/TextRopeTests/TreeInvariantValidation.swift` (carve-out predicate), `Tests/TextBufferTests/RopeBufferDriftTests.swift` (DEF-014, misplaced MARK)
- **Defects closed:** DEF-001 (critical), DEF-007 (medium), DEF-014 except its `testConsecutiveRoundTripsAreIdempotent` bullet
- **Behavior change:** tree shape only. Content, counts, and every public API result are unchanged by construction — every rule is a choice among split points of the same string.
- **Not addressed here:** DEF-014's `RopeTransferIntegrationTests.swift:126-143` round-trip chaining (transfer capability, unrelated to splitting); DEF-009's window-length desync, which is *caused* by the degenerate mid-cluster split this change bounds but is contained separately in `fix-composed-sequence-reads`; DEF-011's quadratic bulk insert, which touches `splitLeaf`'s caller but not its split point.

## Open Questions

1. **The 2049-byte residue.** For `count == 2049` with a 4-byte scalar straddling `[1024, 1025]` (manifestation 3) there is **no** two-leaf shape satisfying both bounds and **no** three-leaf shape either (`3 * minChunkUTF8 == 3072 > 2049`). The proposal picks the boundary minimizing the shortfall below `minChunkUTF8`, which for `NodeTests.swift:42-48` reproduces the currently-pinned **1023** — the value DEF-014 calls "the buggy value". The number is right for the wrong reason today; the change keeps it but rewrites the test to assert the minimal-shortfall property and renames it away from "adjusts when midpoint lands inside". Confirm that reading, or say whether the reviewer intended the forward boundary (1027, left legal / right 1022, a strictly larger shortfall).
2. **Balanced vs. greedy in the two-way case.** The window fallback reuses the greedy construction chunker, which is left-heavy. The primary two-way rule stays midpoint-balanced so no currently-green test changes shape. Should redistribution be balanced everywhere (changing e.g. a 3500-byte combination from `[2048, 1452]` to `[1750, 1750]`), or is preserving today's behavior on the working path worth the inconsistency?
3. **`repairCRLFSeam` overflow plumbing.** The proposed return-siblings approach inserts the third leaf as a sibling of the *right* spine root, which is correct but only reaches `insertIntoNode`'s overflow handling one level up. The alternative — rebuilding both spines through `buildTree` — is simpler to reason about and strictly more expensive. Which does the reviewer want?
4. **Cost of per-operation invariant validation.** DEF-007 asks for at least one seed validating every operation. `verifyTreeInvariants` is O(n) and the stress loop already materializes `rope.content` per operation, so the marginal cost is roughly a constant factor. The proposal adds a dedicated shorter run (2,000 operations) rather than converting one of the four 10,000-operation seeds. Confirm the trade, and whether `TextRopeInsertTests.swift:238`'s 1-in-100 sampling should also become per-step.
5. **Scalar-boundary escape hatch.** The bounded-excess rule permits splitting *inside* a grapheme cluster at a scalar boundary for clusters larger than `maxChunkUTF8`. That is the only way to bound chunk size at all for such input, but it makes leaf-local `Character` iteration see partial clusters — the same condition DEF-009 defends against. Acceptable as the documented pathological residue, or should oversized chunks be preferred over cluster-splitting without limit?
