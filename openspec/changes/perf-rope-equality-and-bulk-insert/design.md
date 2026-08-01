## Context

`TextRope` shipped in M2 with correctness as the goal; the 2026-07-29 four-agent review filed the performance follow-ups as DEF-010 and DEF-011. This change takes the two whose fix is contained inside `TextRope` and does not touch the read path.

Relevant existing machinery, all already present:

- `TextRope.Summary` (`Sources/TextRope/Summary.swift`) — `utf8`, `utf16`, `lines`, `Equatable`, additive via `add(_:)`. Every node carries one; the root's is the whole rope's, maintained by every mutation and already trusted by `isEmpty`, `utf8Count`, `utf16Count`.
- `TextRope.chunkLeaves(from:)` (`Sources/TextRope/TextRope+Construction.swift:12-23`) — walks a `Substring` once, emitting `[Node]` leaves via `chunkEnd(in:)`, which targets `maxChunkUTF8` for long remainders and the midpoint when the remainder is under `maxChunkUTF8 + minChunkUTF8`, then rounds down to a `Character` boundary through `Node.splitPoint(in:targetUTF8:)`.
- `Node.splitInner()` (`Sources/TextRope/Node+Split.swift:11-33`) — already an n-way split into groups of at most `maxChildren`, returning all the new right siblings. It does not care how many children arrived at once.

ADR-004 (UTF-8 storage with cached UTF-16 counts) is what makes the summary early-out possible at all; ADR-007 (no parent pointers, status returned up the call stack) is why `insertIntoLeaf` communicates its overflow through its return value.

## Goals / Non-Goals

**Goals:**
- O(1) rejection of unequal ropes whose root summaries differ, with content equality semantics otherwise unchanged
- First rope-to-rope equality test coverage (DEF-005), including the equal-content/different-shape case the early-out could plausibly break
- Linear-time bulk insert into a non-root leaf, by mirroring the root-leaf branch's single-pass re-chunk
- Preserved invariants after bulk insert: content, per-node summaries, chunk sizes in `[minChunkUTF8, maxChunkUTF8]`, no `\r\n` split across leaves, uniform leaf depth

**Non-Goals:**
- **The `unsafeCharacter(at:)` ASCII fast path (the read half of DEF-011) is deferred.** The ~5× read regression from window materialization plus the `NSString` bridge and two descents per call is untouched here. It interacts with DEF-002 (regional-indicator pairing) and DEF-009 (window-length desync) in `TextRope+ComposedSequences.swift`, and a fast path added before those are settled would have to be re-derived afterwards. DEF-011 stays `open` in `DEFECTS.md` with its first bullet, reduced to the read regression only.
- Chunk-wise streaming comparison for the equal-summary case (compare leaf chunks in order instead of materializing two `String`s). It is the natural next step and would make `==` allocation-free in both directions, but it needs a leaf cursor that does not exist yet and it is not what the per-keystroke path is paying for.
- Hashing, content fingerprints, or any digest beyond the summary already stored.
- `Hashable` conformance for `TextRope`.
- The `balancedSplitPoint` fallback bug (DEF-001) — the bulk-insert path calls `Node.splitPoint(in:targetUTF8:)` via `chunkLeaves`, not `balancedSplitPoint`, so the two do not collide. The CRLF seam repair on the insert unwind still calls `balancedSplitPoint` and keeps DEF-001's behavior exactly as it is today.
- Rebalancing, node merging, or any change to `splitInner()`/`buildTree`.

## Decisions

### 1. Summary comparison as an early-out, not a decision procedure

`TextRope.==` becomes three tiers:

1. `lhs.root === rhs.root` — unchanged identity fast path, the common case for un-mutated copies.
2. `lhs.root.summary != rhs.root.summary` ⇒ `false`, O(1), no allocation.
3. Otherwise `lhs.content == rhs.content`, unchanged.

**Soundness.** `Summary` fields are pure functions of text: `utf8` is the UTF-8 byte count, `utf16` the UTF-16 code unit count, `lines` the `\n` byte count. All three are additive over concatenation, and a node's summary is the sum over its subtree, so the root summary equals that same function applied to `content`. Equal content therefore forces equal summaries; contrapositive, unequal summaries force unequal content. That is the whole justification for tier 2.

The converse is false and must not be assumed: `"ab"` and `"ba"` share a summary, as do any two permutations of the same bytes. Tier 3 is not an optimization that could be dropped later — removing it would make `==` unsound.

**What this newly depends on.** Correctness of `==` now rests on the summary invariant (every node's summary matches its subtree). That invariant is already load-bearing for navigation and for `utf16Count`, and `verifyTreeInvariants` checks it, so this adds no new obligation — but it does turn a summary bug from "wrong offsets" into "wrong equality", which is why the equal-content/different-shape test in tasks 1.1 is the guard that matters.

**Rejected:** caching a content hash on the root. It costs a full pass on every mutation to save a comparison that is already O(1)-rejectable in the common case, and it would need invalidation discipline on every structural edit.

### 2. Single-pass re-chunk on leaf overflow

Today, for a spliced chunk of `n` bytes:

```
insertIntoLeaf   -> splitLeaf()          leaf keeps ~maxChunkUTF8, sibling holds n - maxChunkUTF8 (a full copy)
insertIntoNode   -> while oversized:     splitLeaf() again on the tail, copying it in full each round
                    splitLeaf()
```

Each round copies the whole remaining tail, so the total copying is `n + (n - c) + (n - 2c) + ...` for `c = maxChunkUTF8`, i.e. O(n² / maxChunkUTF8).

After the change:

```
insertIntoLeaf   -> chunkLeaves(from: node.chunk[...])   one pass over n bytes
                    node keeps leaves[0]; returns leaves[1...] as siblings
insertIntoNode   -> inserts the sibling batch at i+1 (no loop), then the existing
                    splitInner() overflow handling runs as before
```

Total copying is O(n), one pass. `insertIntoLeaf`'s return type moves from `Node?` to `[Node]` and the `while` loop at `TextRope+Insert.swift:37-44` is deleted; the `if !siblings.isEmpty` branch keeps the `children.insert(contentsOf:at:)` it already has.

This is verbatim what the root-leaf branch does (`TextRope+Insert.swift:9-12`), minus the `buildTree` — a non-root leaf hands its siblings to its parent instead of becoming a new root.

**Sibling batch size.** A multi-megabyte insert can hand a parent hundreds of new children at once. `splitInner()` is already n-way: it forms `ceil(total / maxChildren)` balanced groups, each between `minChildren` and `maxChildren`, and returns all but the first to *its* parent, which repeats the pattern; at the root, `buildTree(from: [root] + siblings)` absorbs any width. No new code is needed for wide batches — this is the same path `testInsertHugeStringIntoFullInnerNode` already exercises, just reached with more siblings per call.

### 3. Chunk boundaries change; invariants do not

`chunkLeaves` and the repeated-`splitLeaf` loop do not pick the same split points. `chunkEnd` targets `maxChunkUTF8` once the remainder reaches `maxChunkUTF8 + minChunkUTF8` and the midpoint below that; `leafSplitPoint` targets `min((count + 1) / 2, maxChunkUTF8)`. For a 3500-byte chunk the old path yields `[1751, 1749]` and the new one `[2048, 1452]`. Both are legal.

So the structural test in task 2.2 asserts *invariants and content*, not byte-identical leaf shapes: content unchanged, every chunk within `[minChunkUTF8, maxChunkUTF8]`, no `\r\n` split across leaves, every summary consistent, uniform leaf depth. Leaf boundaries are internal and pinned by no public contract; `==` is content-based, so ropes that differ only in shape still compare equal — which is precisely what task 1.1 asserts from the other direction.

A bonus of routing through `chunkLeaves`: its chunks are within `[minChunkUTF8, maxChunkUTF8]` by construction for any input over `maxChunkUTF8`, whereas the old loop reached that only because the last two rounds happened to fall into `leafSplitPoint`'s midpoint branch.

### 4. CRLF safety comes from `Character` boundaries, not from special-casing

`chunkLeaves` → `chunkEnd` → `Node.splitPoint(in:targetUTF8:)` walks the target offset backward until `String.Index(candidate, within: slice) != nil`. `\r\n` is a single Swift `Character`, so no index between them ever validates and the pair cannot be split. The old `splitLeaf` path got its CRLF safety from the same helper. The unwind's seam repair between adjacent children (`TextRope+Insert.swift:47-50`) is untouched and still handles the boundary between the mutated leaf and its left neighbour.

## Risks / Trade-offs

- **Equality regression on equal-content ropes with different tree shapes.** If the summary comparison were ever tightened to something shape-dependent (child count, depth, chunk boundaries), two ropes holding the same text built by different edit histories would wrongly compare unequal. → Mitigation: compare `Summary` only, and pin the case with an explicit test that builds the same content two ways (fresh construction vs. a mutation sequence) and asserts equality, plus one that asserts their leaf shapes actually differ so the test cannot silently degenerate.
- **A stale summary now produces a wrong `==` answer, not just a wrong offset.** → Mitigation: no new invariant is introduced, and `verifyTreeInvariants` already validates summaries after every operation shape in the suite; the stress suite exercises it under randomized edits.
- **`Node.splitLeaf()` becomes unreferenced by production code.** → Mitigation: keep it — `NodeTests.swift:28` pins it, it is the obvious primitive for a future incremental path, and deleting it is unrelated churn.
- **The perf assertion is inherently flaky on shared CI.** A wall-clock ratio between two input sizes is the only observable signal without adding instrumentation. → Mitigation: keep the threshold far from both models (linear ≈4×, quadratic ≈16× for a 4× input growth — assert < 8×), guard against sub-millisecond noise with a minimum measured duration, and mark the task optional so it can be dropped if it proves unstable. Correctness rests on task 2.2, not on the timing.
- **Wide sibling batches stress `splitInner` recursion depth.** A 4 MiB insert produces ~2000 leaves in one call. → Mitigation: covered by the existing n-way `splitInner`; task 2.4 adds a multi-megabyte insert asserting full invariants and correct height.

## Open Questions

1. **Should `chunkLeaves` also absorb the *left* neighbour when re-chunking?** Splicing into the middle of a leaf can leave the mutated leaf's first chunk under `minChunkUTF8` only if the leaf was already undersized; re-chunking the leaf in isolation cannot fix a pre-existing undersize. Current answer: out of scope — the change preserves whatever the leaf already satisfied and does not make it worse. Flagged in case review wants redistribution with the neighbour.
2. **Is the boundary difference from decision 3 acceptable to pin in a spec scenario?** The delta writes chunk bounds normatively but deliberately says nothing about exact split offsets. If a future defragmentation/rebalance pass wants deterministic shapes, that is where to fix them, not here.
3. **Who owns `TextRopeEqualityTests.swift`?** The concurrently proposed `fix-rope-cow-and-equality-coverage` also creates that file for DEF-005, and its proposal already names an "equal-length-but-different content" case as a guard for this change's early-out. If both proceed, the second to land merges into the first's file. The early-out in task 1.4 must not be implemented against an empty file either way — the equal-content/different-shape assertion is its only real guard.
4. **Does TheArchive2's echo suppression need the equal-summary case to be allocation-free too?** If per-keystroke profiles still show `content` dominating (the same-length edit case — e.g. replacing one ASCII character — hits tier 3 every time), the chunk-wise streaming comparison listed under Non-Goals becomes the follow-up. Not resolvable from inside this repo; needs a profile from the consuming app.

## Resolved open questions (2026-08-01)

1. Left-neighbour absorption: confirmed out of scope.
2. Bounds-not-offsets: confirmed — and the re-chunk path adopts ADR-012's grapheme-first rule via the shared helper `fix-rope-split-point` establishes, so this change sequences after it.
3. File ownership: `fix-rope-cow-and-equality-coverage` lands first and owns `TextRopeEqualityTests.swift`; this change extends the file and rebases its Equatable spec delta on that archive.
4. Equal-summary allocation-free comparison: deferred pending a TheArchive2 profile; stays in Non-Goals.
