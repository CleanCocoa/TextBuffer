## Context

`Node.maxChunkUTF8 == 2048` and `Node.minChunkUTF8 == 1024` (`Sources/TextRope/Node.swift:10-11`). Note the relation that drives every rule below:

```
maxChunkUTF8 == 2 * minChunkUTF8
```

Three call paths choose a split point in a UTF-8 byte string:

| Caller | Site | Input size | Today's helper |
| --- | --- | --- | --- |
| `TextRope.init` / bulk re-chunk | `TextRope+Construction.swift:25-41` (`chunkEnd`) | unbounded | `splitPoint` (backward only) |
| `Node.splitLeaf` on insert overflow | `Node+Split.swift:2-9` → `leafSplitPoint:35-43` | unbounded | `splitPoint` (backward only) |
| leaf merge / CRLF seam repair | `TextRope+Delete.swift:156` (`combinedLeaf`), `TextRope+Insert.swift:78` (`repairCRLFSeam`) | ≤ 4096 | `balancedSplitPoint:45-73` |

`balancedSplitPoint` computes the only window that can satisfy both bounds for a two-way split:

```
low  = max(minChunkUTF8, count - maxChunkUTF8)
high = min(maxChunkUTF8, count - minChunkUTF8)
```

and searches it bidirectionally from the midpoint. That part is correct. Line 72 — the fallback taken when the window contains no `Character` boundary — discards the window entirely and calls `splitPoint(in:targetUTF8: (count + 1) / 2)`, an unbounded backward walk. Every DEF-001 manifestation is a consequence.

ADR-004 (UTF-8 storage), ADR-006 (always-rooted) and SPEC.md §4.2/§4.3 are unaffected: this change picks among split points of the same string and never alters content, counts, or the public API.

## Goals / Non-Goals

**Goals:**
- Repair all four DEF-001 manifestations at one site
- State chunk-size bounds so they are simultaneously *achievable* and *checkable*, so per-operation invariant validation (DEF-007) can be turned on without false failures
- Preserve the tree shape produced on every path that is currently correct, so no green test changes expectations except the one DEF-014 names
- Leave the invariant validator strictly stronger than it is today
- Extract the merge machinery into the spec-named `Sources/TextRope/Node+Merge.swift`, symmetric with `Node+Split.swift` — pure file movement (DEF-006c, added 2026-08-01)

**Non-Goals:**
- Rebalancing beyond what the split point itself decides — no global rebalance pass
- DEF-009's window-length desync at the composed-sequence reader (contained in `fix-composed-sequence-reads`)
- DEF-011's quadratic bulk insert, which changes `splitLeaf`'s *caller*, not its split point
- Performance work: the window search is O(window width) index validations, unchanged in order

## Arithmetic: why the window collapses

Every leaf holds at most `maxChunkUTF8 == 2048` bytes, so a merge of two adjacent leaves has

```
count <= 2 * maxChunkUTF8 == 4096
```

and redistribution is only attempted when `count > maxChunkUTF8`, i.e. `count ∈ (2048, 4096]`. Window width over that interval:

```
width(count) = high - low + 1
             = count - 2047        for  2048 <= count <= 3072      (low == 1024, high == count - 1024)
             = 4097 - count        for  3072 <= count <= 4096      (low == count - 2048, high == 2048)
```

The three widths the reviewers called out:

| `count` | `[low, high]` | width | reachable by |
| --- | --- | --- | --- |
| 2048 | `[1024, 1024]` | 1 | only `repairCRLFSeam`, which calls unconditionally; `combinedLeaf` returns a single leaf first |
| 2049 | `[1024, 1025]` | 2 | delete redistribution of two undersized leaves (DEF-001 manifestation 3) |
| 4096 | `[2048, 2048]` | 1 | two full 2048-byte leaves rejoined (manifestations 1 and 2) |
| 3072 | `[1024, 2048]` | 1025 | the widest window; the comfortable case |

A window of width `w` contains no `Character` boundary exactly when one grapheme cluster spans all `w + 1` offsets in it. At `w == 1` that needs a 2-byte cluster — **`\r\n` qualifies**, and so does any 2-byte scalar. At `w == 2` a 3- or 4-byte scalar qualifies. So the fallback is not the degenerate ZWJ-chain path the comment at `Node+Split.swift:71` claims: it is reached by plain ASCII line endings, deterministically, at `count == 4096`. That comment is wrong on both counts — the trigger and the residue (it says the cluster gets split across chunks; in fact `splitPoint`'s backward walk lands on a legal boundary and the *residue is an oversized right chunk*).

**Feasibility of a two-way split.** Both sides land in `[min, max]` iff a boundary exists in `[low, high]`. When it does not, no two-leaf shape is legal, full stop.

**Feasibility of a three-way split.** Three chunks each ≥ `minChunkUTF8` need `count >= 3 * minChunkUTF8 == 3072`; each ≤ `maxChunkUTF8` needs `count <= 3 * maxChunkUTF8 == 6144`, always true here. Combined with the width table: an empty window at `count >= 3072` implies `width <= 1025` and three-way is available. At `count == 4096` (manifestations 1 and 2) it is available.

**The residual band.** `count ∈ (2048, 3072)` with an empty window admits neither a legal two-way nor any three-way split. Manifestation 3 (`count == 2049`) sits here. This band is *provably* unsatisfiable, which is why `minChunkUTF8` has to become a best-effort bound with a stated carve-out rather than a lie the validator samples around.

**The single-leaf case.** `count <= maxChunkUTF8 == 2 * minChunkUTF8` means any two-way split undersizes a side, and no split is needed. `combinedLeaf` already short-circuits (`TextRope+Delete.swift:151`); `repairCRLFSeam` does not, and today happily bisects a 100-byte combination into two ~50-byte leaves because `low > high` makes the search loop body unreachable and drops straight to line 72. The single-leaf rule fixes that second bug in passing.

## Decisions

### D1. `rebalancedChunks(in:) -> [Substring]` replaces `balancedSplitPoint`

The two merge/repair call sites want chunks, not an index, because the answer is sometimes one chunk and sometimes three. The rules, in order:

1. `count <= maxChunkUTF8` → `[slice]`. Single leaf.
2. Boundary search in `[low, high]`, bidirectional from `target = (count + 1) / 2`, nearest wins, ties resolve to the lower offset (matching today's backward-first order). Found → `[left, right]`, both in `[min, max]` by construction.
3. Window empty → balanced redistribution (decided 2026-08-01, resolving open question 2 toward balance everywhere — the fallback fires only on paths that are broken today, so no green test shifts). For `count >= 3 * minChunkUTF8` this is a three-way split with targets at `count / 3` and `2 * count / 3`, each moved to the nearest `Character` boundary with minimal deviation, ties to the lower offset; for the residual band it is the minimal-deviation two-way split of D3.

Rule 2 is the only rule that fires on every currently-correct path, so no green test changes shape.

Worked example, manifestations 1 and 2 (`count == 4096`, `"a"×2047 + "\r\n" + "b"×2047`): rule 2's window is `[2048, 2048]`, and offset 2048 is the CR/LF interior — empty. Rule 3's three-way targets are 1365 and 2730; both are plain-ASCII boundaries → `[1365, 1365, 1366]`. All three in `[1024, 2048]`, `\r\n` intact inside chunk 2.

### D2. `leadingChunkEnd(in:) -> String.Index` unifies `leafSplitPoint` and `chunkEnd`

`Node+Split.swift:35-43` and `TextRope+Construction.swift:25-41` are the same function with different thresholds and the same backward-only defect. One helper:

1. `count <= maxChunkUTF8` → `endIndex`.
2. `count >= maxChunkUTF8 + minChunkUTF8` (== 3072) → greedy: the largest `Character` boundary ≤ `maxChunkUTF8`. The left chunk is ≥ `minChunkUTF8` unless one cluster spans `[1024, 2048]`; the remainder is ≥ `count - maxChunkUTF8` ≥ `minChunkUTF8` by the branch condition, and is re-chunked by the caller's loop.
3. Otherwise (`2048 < count < 3072`) → balanced: window is `[minChunkUTF8, count - minChunkUTF8]` (both `max`/`min` clamps are inactive in this band), bidirectional search from the midpoint. Note this band is exactly the residual band, so three-way is never applicable here and rule 3 of D1 cannot recurse forever.

Rule 3 is what fixes manifestation 4. Existing `NodeTests` expectations survive: 2049 ASCII bytes → 1025; 10,000 bytes → 2048; `1024×"a" + "\r\n" + 1023×"b"` → 1024; 513 × 😀 (2052 bytes) → 1024.

### D3. Grapheme-first bounds, and the starvation predicate (ADR-012)

- **Splits fall on `Character` boundaries only.** No split point ever falls inside a grapheme cluster — not even at a Unicode scalar boundary. The scalar-boundary escape hatch considered earlier is rejected (ADR-012); there is no bounded-excess constant.
- **`maxChunkUTF8` yields only to a whole cluster.** A chunk may exceed it only when the chunk is a **single grapheme cluster** larger than 2048 bytes — the cluster occupies one whole-cluster leaf of whatever size it needs. That exception is exact (the chunk is one `Character`), which is what makes the rule statable in a spec and assertable by the validator.
- **`minChunkUTF8` is best-effort under starvation.** A leaf may fall below it only when, for each adjacent sibling `S`, `leaf.utf8 + S.utf8 > maxChunkUTF8` **and** the combined slice has no `Character` boundary in its `[low, high]` window. That predicate is decidable from the tree alone, so the invariant validator can assert the strong bound everywhere else instead of skipping the check.
- **Tie-break inside the residual band.** Among the boundaries in the hard window `[count - max, min(max, count - 1)]`, pick the one minimizing `shortfall(p) = max(0, min - p) + max(0, min - (count - p))`; ties resolve to the lower offset. For manifestation 4's `1022 | 😀 | 1027` layout this picks 1026 (shortfall 1) instead of today's 1022 (shortfall 2). For `NodeTests.swift:42-48`'s `1023 | 😀 | 1027` layout it picks 1023 (shortfall 1; the alternative 1027 leaves 1022, shortfall 2) — the same number the test pins today, now for a stated reason (resolved 2026-08-01: the test is renamed to state it).

### D4. Termination and bounds

- D1 rule 3 computes at most three chunks directly from fixed fractional targets — there is no loop to terminate. D2's construction chunking loop terminates because `leadingChunkEnd` always returns an index strictly greater than `startIndex` (its rule 2 requires a boundary ≥ some positive offset; its rule 3's hard-window search is non-empty because `count > maxChunkUTF8`, and the whole-cluster rule returns `endIndex`), so the remaining slice strictly shrinks.
- D2 does not recurse, and D1 does not call itself, so there is no mutual recursion.
- No merge/split oscillation: `rebalancedChunks` is a pure function of the combined slice. When it returns a short chunk it is because the residual-band predicate holds, and re-running the same merge on the same pair returns the identical shape — a fixed point that the validator now *accepts* rather than flags. Manifestation 3's `[1023, 1026]` is that fixed point; the change makes it legal-and-explained instead of illegal-and-invisible.
- Every rule preserves the `\r\n` invariant for free: `\r\n` is a single `Character`, and under ADR-012 every split point is a `Character` boundary — so no split can ever fall between CR and LF. The invariant is absolute, not a guarded special case.

### D5. Call-site plumbing for the three-chunk result

- `combinedLeaf` (`TextRope+Delete.swift:149-159`) already appends spill-over into `merged` and returns the tail; it appends `chunks.count - 1` leaves and returns the last. One chunk means the pair truly merged — that is the existing `<= maxChunkUTF8` early return, which stays.
- `repairCRLFSeam` (`TextRope+Insert.swift:70-88`) rewrites `leftLeaf` and `rightLeaf` in place and cannot express a third leaf. It becomes `repairCRLFSeam(...) -> [Node]`: chunk 0 into `leftLeaf`, the final chunk into `rightLeaf`, any middle chunk returned to `insertIntoNode`, which splices it after `children[i]` and then re-runs the existing `children.count > maxChildren → splitInner()` check at `:51-53`. That path already exists for the sibling returned by a recursive insert. The alternative — replacing both spines via `buildTree` — is simpler but re-allocates the seam's whole subtree; rejected 2026-08-01 in favor of the sibling return (open question 3).
- Both spines' summaries are already recomputed bottom-up at `:82-87`; a spliced middle leaf needs the same treatment on the right spine.

### D6. Invariant validator and DEF-007

`Tests/TextRopeTests/TreeInvariantValidation.swift:52-61` asserts `size >= minChunkUTF8` for every leaf of a non-leaf root. Under D3 that is *almost* right — it must become "≥ min, or the starvation predicate holds against both neighbours", which is stricter than skipping and stricter than today for every leaf that has a merge partner. The upper bound stays assertable exactly: `size <= maxChunkUTF8`, or the chunk is a single grapheme cluster (the whole-cluster leaf). No byte tolerance anywhere.

With the predicate in place, per-operation validation (DEF-007) cannot produce false failures, so at least one seeded stress run validates after every operation instead of every hundredth. `verifyTreeInvariants` is O(n) and the loop already materializes `rope.content` per operation, so the marginal cost is a constant factor on an already-linear step.

## Risks / Trade-offs

- **Tree shape churn.** Rule 2 covers every path that works today, so shapes only change where they were illegal. The one deliberate exception is `repairCRLFSeam` on small combinations (previously bisected, now left as one leaf) — a shape improvement that could still surprise a test pinning leaf counts. → Mitigation: run the full suite before touching any expectation, and record every changed expectation in tasks with its justification.
- **Three-way splitting raises child counts.** A seam repair that adds a leaf can push an inner node over `maxChildren` and cascade a split during what used to be an in-place fix. → Mitigation: the cascade path is the existing `splitInner` one; the CRLF stress tests at `TextRopeStressTests.swift:262-352` already drive it, and per-operation validation will catch a mishandled cascade at the operation that caused it.
- **The residual band stays imperfect.** `[1023, 1026]` remains the output for manifestation 3. The change makes it provably optimal and documented rather than making it disappear. → Mitigation: the regression test asserts the *optimality* (no boundary in the window; the alternative split has a larger shortfall), so if someone later widens the band they must revisit it deliberately.
- **A cluster larger than `maxChunkUTF8` yields one oversized whole-cluster leaf.** It is never split (ADR-012), so leaf-local `Character` iteration stays intact and DEF-009's mid-cluster seam becomes impossible; the cost is a locally more expensive edit path for crafted input (Zalgo, long ZWJ chains). → Mitigation: the validator accepts an oversized leaf only when its chunk is a single `Character`, and the behavior is stated in the spec rather than in a comment.
- **Per-operation validation slows CI.** One 2,000-operation seed, not all four 10,000-operation seeds. → Mitigation: record the measured wall-clock delta in the verification task; if it exceeds a few seconds, drop the dedicated run's operation count rather than its per-operation validation.

## Alternatives Considered

- **Clamp `splitPoint`'s walk to `low` and stop there.** Minimal diff, fixes manifestation 3's undersized side, but leaves manifestations 1 and 2 with no answer at all (their window is a single illegal offset), so it would have to return "no split possible" anyway.
- **Allow the merge to be skipped when no legal split exists.** Leaves the pre-merge shape, which for manifestation 3 is `[1000, 1049]` — two undersized leaves instead of one. Strictly worse.
- **Relax split points to Unicode scalar boundaries.** Would make the residual band satisfiable for multi-scalar clusters (flags, ZWJ chains) but not for the single-scalar case that manifestations 3 and 4 actually hit, while breaking leaf-local `Character` iteration. Rejected outright by ADR-012 — no split ever crosses a `Character` boundary; a cluster larger than `maxChunkUTF8` occupies one whole-cluster leaf instead.
- **Pull bytes from a farther sibling.** The general fix for undersized leaves in a B-tree, and out of scope here: manifestation 3's rope is 2049 bytes in total, so no farther sibling exists and the band would remain.

## Resolved open questions (2026-08-01, ADR-012)

- **Chunk-bounds regime**: grapheme-first per ADR-012. Splits only at `Character` boundaries; bounds MUST except under provable boundary starvation, where the nearest-boundary minimal-deviation split (or a whole-cluster leaf) is taken. The scalar-boundary escape hatch (D3) is **dropped** — no split ever crosses a `Character` boundary. The validator gains the exact per-leaf starvation predicate instead of a tolerance.
- **The 1023 residue**: correct by the minimal-deviation rule. `NodeTests`' pinned expectation stays numerically and the test is renamed to state the starvation reasoning (resolves open question 1 in the reviewer's favor).
- **Redistribution policy**: balanced, not greedy — no green test shifts (open question 2).
- **`repairCRLFSeam` plumbing**: return overflow siblings to `insertIntoNode`; no `buildTree` spine rebuilds (open question 3).
- **DEF-007 cost**: add one dedicated 2,000-op seed validating invariants after every operation; the four 10,000-op seeds keep 1% sampling; `TextRopeInsertTests` stays sampled (open question 4).
- **Merge no-retry**: a leaf out of bounds under proven starvation is accepted by subsequent merge scans without re-attempting rebalance (new, from ADR-012).
- **Scope addition (DEF-006c)**: extract the merge machinery into the spec-named `Sources/TextRope/Node+Merge.swift`, symmetric with `Node+Split.swift` — pure file movement, disclosed here rather than by silent task edit.
