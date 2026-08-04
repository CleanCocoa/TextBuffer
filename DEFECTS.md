# Defect Tracker

Defects filed against 0.9.1 (`5cf2638`; found at 0.9.0 by the 2026-07-29 four-agent review of the M2 gap-closure fold `0.8.2..0.9.0`). **Resolved in 0.10.0** (2026-08-04) except the two explicitly deferred halves: DEF-011's read fast path (benchmark-driven) and DEF-012's O(log n) queries (M3 Rope Queries). Line references in the defect bodies describe the 0.9.1 code they were filed against.

DEF-015 and DEF-016 were filed against the not-yet-pushed 0.10.0 (`438c041`) by the 2026-08-04 post-release review; both repros verified against that tag; both **resolved in 0.10.1** (2026-08-04). Their line references describe 0.10.0 code. DEF-017, discovered during the DEF-016 fix, was **fixed on the 0.11.0 train** (2026-08-04, change `fix-delete-merge-starvation`); DEF-011's read fast path followed on the same train (2026-08-04, change `perf-read-fast-path`), leaving only DEF-012's O(log n) queries (M3 Rope Queries) deferred.

Status values: `open`, `in-progress`, `fixed`, `wontfix`.

## Triage (2026-07-31)

| Defect | Disposition |
|---|---|
| DEF-001, DEF-007, DEF-014 | Specced: `fix-rope-split-point` (35 tasks). Exception: DEF-014's round-trip-chaining bullet is unassigned. |
| DEF-002, DEF-009 | Specced: `fix-composed-sequence-reads` (23 tasks) |
| DEF-003, DEF-005, DEF-008 | Specced: `fix-rope-cow-and-equality-coverage` (25 tasks) |
| DEF-010, DEF-011 (quadratic insert) | Specced: `perf-rope-equality-and-bulk-insert` (17 tasks) |
| DEF-013, DEF-012 (docs half) | Specced: `docs-rope-disclosure` (22 tasks) |
| DEF-004 | Decided 2026-08-01: enforce the trap. Tasks join `fix-composed-sequence-reads` (owns the navigation spec delta). |
| DEF-006 | Decided 2026-08-01: (a) NSRange → ADR-013, `foundation-free-textrope` change to be authored, lands last; (b) replace spec amended to observable behavior, rides that change; (c) `Node+Merge.swift` extracted in `fix-rope-split-point`, disclosed; Purpose-TBD headers fold into `docs-rope-disclosure`. |
| DEF-011 (read fast path) | ~~Deferred — benchmark-driven; interacts with `fix-composed-sequence-reads`~~ Resolved 2026-08-04 by `perf-read-fast-path` |
| DEF-012 (O(log n) queries) | Deferred — M3 Rope Queries |

Implementation order constraint: `fix-rope-cow-and-equality-coverage` before `perf-rope-equality-and-bulk-insert` (both touch the Equatable requirement and `TextRopeEqualityTests.swift`; the perf change's spec delta rebases on the former's archive).

## Decisions (2026-08-01 grilling)

Recorded here for traceability; architectural detail in ADR-012 (grapheme-first chunk bounds) and ADR-013 (Foundation-free TextRope).

- **Release**: one combined **0.10.0** (no interim 0.9.2). Order: fix-rope-split-point → fix-composed-sequence-reads → fix-rope-cow-and-equality-coverage → perf-rope-equality-and-bulk-insert → docs-rope-disclosure → foundation-free-textrope → release. Push held until proposals reflect these decisions.
- **DEF-004**: trap enforced; preconditions precede the empty-range early returns in `content(in:)` and the composed-sequence APIs.
- **Chunk bounds**: grapheme-first per ADR-012; DEF-009's fallback graduates to a precondition; `NodeTests`' 1023 renamed as the reasoned minimal-shortfall case; no scalar-boundary escape.
- **CHANGELOG**: retro-disclosures amend the released `0.9.0` section in place (historical accuracy over append-only); `findLeaf` fixes stay undisclosed (internal, unreachable at 0.8.2).
- Minor calls: composed-read window cap fixed at 4096 UTF-16 units with silent full-document fallback; TSan remains a documented developer-local gate; DEF-008 uses a height-3 template; DEF-007 adds a dedicated 2,000-op per-operation-validated seed alongside the four sampled 10k seeds; balanced (not greedy) redistribution; `repairCRLFSeam` returns siblings; archived foundation tasks.md gets a disclosed correction note for the false Equatable tick; DEF-014's round-trip-chaining bullet joins `fix-rope-cow-and-equality-coverage`; equal-summary allocation-free equality deferred pending a TheArchive2 profile.

## Critical

### DEF-001: `balancedSplitPoint` fallback ignores its legal window — `fixed`

Fixed 2026-08-03 (`16ce570`, `1e6a6aa`): grapheme-first bidirectional boundary search with balanced 1-3-way redistribution (`rebalancedChunks`), minimal-shortfall starved splits, whole-cluster oversized leaves per ADR-012; `repairCRLFSeam` returns siblings. The exact validator additionally caught and `1e6a6aa` fixed a fifth manifestation not in the original report: insert-overflow and construction splits starved in isolation without consulting adjacent leaves. All four original repros re-verified via `NodeSplitPointTests` (manifestations 1/2 now yield `[1365, 1365, 1366]`).

`Sources/TextRope/Node+Split.swift:72`. When `[low, high]` contains no `Character` boundary, the fallback walks backward from the midpoint unbounded, violating chunk-size invariants. One root cause, four manifestations:

1. **Insert CRLF seam repair → oversized leaf (deterministic, ASCII-only).** `repairCRLFSeam` (`TextRope+Insert.swift:78`) on a 4096-byte combination has a 1-byte window that is exactly the CR/LF interior; fallback yields `[2047, 2049]`.
   ```swift
   let base = String(repeating: "a", count: 2047) + "\r" + String(repeating: "b", count: 2047)
   var rope = TextRope(base)          // leaves [2048, 2047]
   rope.insert("\n", at: 2048)        // leaves [2047, 2049]  — 2049 > maxChunkUTF8
   ```
2. **Delete CRLF rejoin of two 2048-byte leaves → same `[2047, 2049]`, every time.** `TextRope+Delete.swift:131-141` → `combinedLeaf:156`.
   ```swift
   let a = String(repeating: "a", count: 2047) + "\r"
   let m = String(repeating: "m", count: 2048)
   let b = "\n" + String(repeating: "b", count: 2047)
   var rope = TextRope(a + m + b)
   rope.delete(in: NSRange(location: 2048, length: 2048))   // leaves [2047, 2049]
   ```
3. **Delete redistribution → undersized leaf that is a stable fixed point.** At `count = 2049` the window is 2 bytes wide; a 4-byte character straddling it yields `[1023, 1026]`, and re-running the merge reproduces the same split, so it never self-heals (persisted 300+ ops under fuzzing, seed 2 op 983).
   ```swift
   let part2 = String(repeating: "c", count: 1022) + "\u{1F600}" + String(repeating: "d", count: 1022)
   var rope = TextRope(String(repeating: "a", count: 2048) + String(repeating: "b", count: 2048) + part2)
   rope.delete(in: NSRange(location: 1000, length: 4095))   // leaves [1023, 1026]
   ```
4. **`leafSplitPoint` backward-only walk → sub-minimum chunk on multi-byte midpoint.** `Node+Split.swift:42` + `:75-89`; a single emoji straddling the midpoint of a 2048-byte leaf plus a 1-char ASCII insert yields a 1022-byte leaf. `Tests/TextRopeTests/NodeTests.swift:42-48` currently pins the buggy value (asserts 1023).

**Fix direction:** clamp the fallback into `[low, high]` with bidirectional search; when the window holds no boundary, split three ways or (for `count <= 2 * minChunkUTF8`) emit a single leaf. One site fixes all four manifestations. Update `NodeTests.swift:42-48` expectation.

### DEF-002: Regional-indicator pairing breaks in composed-sequence reads — `fixed`

Fixed 2026-08-03 (`03ebba7`, change `fix-composed-sequence-reads`): `windowStart` snaps back over the contiguous RI run (leaf-chunk walk, one descent, no added descents on non-RI reads), capped at 4,096 UTF-16 units with silent full-document fallback. Repro and 400-offset sweep pinned at rope and buffer-drift levels.

`Sources/TextRope/TextRope+ComposedSequences.swift:32-51` (`expandingWindow`), introduced by `9570025`. UAX #29 GB12/GB13 pairs regional indicators counting from text start; a ±128-unit window whose start lands on an odd RI boundary flips pairing parity, and the mispaired result sits strictly inside the window so the edge-touch retry never fires. **Content-visible divergence** from `MutableStringBuffer` — the only defect that returns wrong text:

```swift
let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)   // 🇩🇪 × 40
MutableStringBuffer(text).unsafeCharacter(at: 130)  // "🇩🇪"
RopeBuffer(text).unsafeCharacter(at: 130)           // "🇪🇩"  — wrong
```

Affects any document > 129 UTF-16 units containing an RI run (136/400 offsets wrong at 100 flags); `SendableRopeBuffer` identical. Combining marks and ZWJ chains verified unaffected.

**Fix direction:** walk `windowStart` backward over the contiguous RI run (`U+1F1E6...U+1F1FF`) to a parity-correct anchor, capped with fallback to full materialization.

### DEF-003: Single-owner delete always path-copies — `fixed`

Fixed 2026-08-03 (`46ee53f`, change `fix-rope-cow-and-equality-coverage`): the descent captures `children[i].summary.utf16` instead of aliasing the node. Pinned by on-path identity tests `testDeleteOnSingleOwnerRopeMutatesInPlace` (strengthened), `testDeleteOnSingleOwnerMultiLevelRopeKeepsOnPathNodeIdentity`, and insert/replace twins.

`Sources/TextRope/TextRope+Delete.swift:56`: `let child = node.children[i]` holds a second strong reference still live when `ensureUniqueChild(at:)` runs, so `isKnownUniquelyReferenced` is always false and every delete path-copies even with one owner. Violates `openspec/specs/rope-delete/spec.md:63-65`. `testDeleteOnSingleOwnerRopeMutatesInPlace` (`TextRopeDeleteTests.swift:396-406`) passes because it checks the root and an off-path child only.

**Fix direction:** capture `node.children[i].summary.utf16` instead of the node; strengthen the test to assert identity of the on-path child.

## Medium

### DEF-004: Empty-range reads bypass out-of-bounds preconditions — `fixed`

Fixed 2026-08-03 (`03ebba7`, change `fix-composed-sequence-reads`): preconditions moved ahead of the empty-range early returns in `content(in:)` and both composed-sequence APIs; six process-exit tests pin past-end, negative, and `NSNotFound` locations. 0.10.0 behavior tightening.

`TextRope+Navigation.swift:30` and `TextRope+ComposedSequences.swift:9`: `length == 0` early-returns before the preconditions, so `content(in: NSRange(location: 500, length: 0))` (also negative / `NSNotFound` locations) silently returns `""` on a 5-char rope. Violates `openspec/specs/rope-utf16-navigation/spec.md:75-77`. Flagged in the 2026-07-28 audit; not fixed by the fold and copied into the new API. Contained at the buffer layer (RopeBuffer guards with `contains(range:)`).

### DEF-015: Empty-operand mutations bypass out-of-bounds preconditions — `fixed`

Fixed 2026-08-04 (`3f67a1c`, change `fix-empty-operand-oob-mutations`): the DEF-004 decision applied identically to the mutation side — preconditions moved ahead of the empty-operand early returns in `delete(in:)` and `insert(_:at:)`, so empty out-of-bounds operands trap; in-bounds empty operations remain no-ops (the early returns still precede `ensureUnique()`, so no path copy). The `NSRange` delete wrapper inherits the fix through forwarding, untouched. Five process-exit tests pin the traps (`Range<Int>` delete pair, empty-string insert pair, `NSRange` wrapper forward); no-op pins cover the in-bounds boundary offsets. 0.10.1 behavior tightening.

The delete/insert sibling of DEF-004, which fixed only the read APIs. Both mutation primitives early-return on an empty operand *before* their bounds preconditions:

- `TextRope+Delete.swift:6`: `if utf16Range.isEmpty { return }` precedes both preconditions, so `TextRope("hello").delete(in: 500..<500)` silently succeeds. Violates the canonical trap requirement (`openspec/specs/rope-delete/spec.md` "Out-of-bounds range traps": `upperBound > utf16Count` MUST trap — an empty range at 500 has `upperBound == 500`). Verified 2026-08-04.
- `TextRope+Insert.swift:4`: `if string.isEmpty { return }` precedes the offset precondition, so `TextRope("hello").insert("", at: 500)` silently succeeds. The insert spec states the offset "MUST be in the range `0...utf16Count`" but has no trap scenario; its empty-string no-op scenario uses an in-bounds offset only.

The `NSRange` wrapper (`Sources/TextBuffer/TextRope+NSRange.swift:28-33`) validates only `NSNotFound`/negative encodings and forwards `location ..< location + length`, its doc stating the primitive "owns the bounds checks against `utf16Count`" — so `delete(in: NSRange(location: 500, length: 0))` silently succeeds too. `replace(range:with:)` is unaffected (its own preconditions run before composing). Buffer layer contained as with DEF-004 (`contains(range:)` guards throw first).

### DEF-016: Insert and delete create leaf seams inside grapheme clusters — `fixed`

Fixed 2026-08-04 (`ceeeda6`, change `fix-grapheme-seam-repair`): the predicate generalized per the root-cause note — the CRLF machinery was the special case. `crlfSeam(between:)` became `graphemeSeam(between:)` (left subtree's last `Character` + right subtree's first `Character` concatenate to fewer than two `Character`s, Swift stdlib segmentation only per ADR-013), in producer/validator agreement with `leafSeamViolations`; `repairCRLFSeam` renamed `repairGraphemeSeam` unchanged in body; the seam checks run unconditionally at the insert post-splice site and the delete merge gate (`hasGraphemeSeam` or-term), plus both merge loops. Both repros re-verified by hand: insert now yields `[1537, 1536, 1025]`, delete `[2047, 2048]`, both seam-violation-free; regression suite `GraphemeSeamRepairTests` (11 cases incl. ZWJ/variation-selector boundary cases, RI-parity pins, CRLF non-regression). The stress-alphabet half of the coverage gap was deferred here (adding lone extenders exposed the distinct pre-existing DEF-017) and landed with the DEF-017 fix (2026-08-04, change `fix-delete-merge-starvation`): `stressCharset` now carries `\u{301}`/`\u{200D}`/`\u{FE0F}` and all five pinned seeds run green over the extended pool.

ADR-012 enforces `Character` boundaries at *split points*, but a seam-spanning cluster can also form by *adjacency change*, and seam repair handles only the CRLF case. Two verified repros (2026-08-04, both flagged by the test-side `leafSeamViolations` validator, suite otherwise green):

- **Insert** (`TextRope+Insert.swift:90-91`): inserting a grapheme extender at an existing leaf boundary — `"\u{301}"` at offset 2048 in 4,096 ASCII `a`s — splices at leaf-local offset 0 of the right leaf. The overflow re-chunk yields leaves `[2048, 1025, 1025]`; no edge chunk is undersized, so `redistributeStarvedEdge` skips, and the seam check covers only `crlfSeam`. The cluster `a\u{301}` spans the seam after leaf 0.
- **Delete**: deleting a base character whose extender starts the next leaf exposes a new adjacency — `TextRope("a"×2048 + "b\u{301}" + "c"×2045)`, `delete(in: 2048..<2049)` removes the `b`, leaving the right leaf starting with `\u{301}` next to leaf 0's trailing `a`. The delete path's seam handling is likewise `crlfSeam`-only, and the right leaf is not undersized, so no merge fires.

Violates `openspec/specs/rope-core-types/spec.md:222-224` ("no grapheme cluster SHALL span a chunk seam"). Reads remain code-unit-faithful — `content(in:)` slices by UTF-16 offsets and concatenation preserves counts, so no wrong content is observable and DEF-009's window-length precondition never fires — but the structural invariant that precondition's justification (and ADR-012's reasoning generally) rests on is broken. Coverage gap: the stress alphabet never inserts lone extenders, so the per-operation validator (DEF-007) never sees the shape. Root-cause note: `\r\n` is just one grapheme cluster — the CRLF-only seam machinery is the special case of the repair this defect requires.

### DEF-017: Delete-path merge starves a leaf in isolation without consulting the other-side neighbor — `fixed`

Fixed 2026-08-04 (`4a9cfbb`, change `fix-delete-merge-starvation`): other-side consultation at the merge's starved-emission site — `combinedLeaf` makes a single redistribution attempt between an undersized emitted chunk and `merged.last`, gated by the shared `Node.isBoundaryStarved` (producer/validator agreement with `isStarvationJustified`), preserving the no-retry discipline — plus the `absorbableStarvedEdge(between:and:)` gate at the deletion path's ancestor levels (`deleteFromInner`'s merge-gate or-term and `mergeUndersizedInnerNodes`' combine disjunct, funneling cross-parent pairs through `combinedInner` into the same-parent repair). Adjacency is defined document-order over the flattened leaf sequence, in producer/validator agreement (rope-core-types clarification). The repro shape now resolves to `[1049, 1048, 1027]` (cross-parent variant identically at the common ancestor); the two-sided-starved trio remains an accepted fixed point. Stress alphabet extended with the three lone extenders (`\u{301}`, `\u{200D}`, `\u{FE0F}`) and all five pinned seeds run green over it, per-op seed `0xDEF007` validated byte-exactly every operation.

Filed 2026-08-04 during `fix-grapheme-seam-repair` task 5.3 (discovered by extending the stress alphabet with lone grapheme extenders; reproduced byte-identically on pre-change 0.10.x sources, so it is not introduced by that change). The delete-path analogue of DEF-001's fifth manifestation, which was fixed for insert-overflow and construction only (`redistributeStarvedEdge`).

`Node+Merge.swift` (`mergeUndersizedLeaves` → `combinedLeaf` → `rebalancedChunks`): when an undersized leaf combines rightward and the combination is boundary-starved, the minimal-shortfall split's undersized output is accepted against *that pair* — but the merge never checks whether the *other-side* neighbor could absorb it, violating ADR-012's per-adjacent-leaf starvation predicate (`openspec/specs/rope-core-types/spec.md`: undersized only when starved against **each** adjacent sibling). Deterministic shape from stress seed `0xDEF007` + extender alphabet, iteration 48: leaves `[…, 1074, 1024, 1034, …]`, a delete across the 1024|1034 seam leaves `[1024→1023, 1034→1027]`; the pair's 2050-byte combination is starved (a `U+1F389` spans its `[1024, 1026]` window — no extender involved) and re-splits to the same `[1023, 1027]` fixed point, while the left neighbor's 2097-byte combination has boundaries throughout its `[1024, 1073]` window, so `chunkSizeViolations` reports "Leaf has 1023 UTF-8 bytes … redistribution with leaf (combined 2097 bytes) would conform". All five pinned stress seeds hit the class once the alphabet includes extenders (the RNG stream reshuffle exposes it; the mechanism needs only old-alphabet emoji). Blocks the stress-alphabet extension DEF-016's coverage gap calls for. Likely fix: consult the other-side neighbor after a starved combination, mirroring the insert path's `redistributeStarvedEdge` — a merge-path mechanism change deliberately out of `fix-grapheme-seam-repair`'s scope.

### DEF-005: `TextRope: Equatable` has zero tests — `fixed`

`TextRope.swift:39`. Archived task `2026-07-29-m2-rope-foundation/tasks.md:36` is ticked naming Equatable coverage in `TextRopeConstructionTests.swift`; no rope-to-rope equality assertion exists anywhere. Spec: `openspec/specs/rope-core-types/spec.md:102-113`.

Fixed 2026-08-03 (`46ee53f`): `TextRopeEqualityTests.swift` covers the six spec cases, including equal-content/different-shape (leaf shapes asserted to differ) and equal-summary/different-content; the archived task's tick carries a disclosed correction note.

### DEF-006: Canonical spec contradictions and silent task rewrites — `fixed`

- ~~`openspec/specs/rope-target-setup/spec.md:7` says TextRope "MUST NOT depend on ... Foundation's NSRange"; three sibling canonical specs mandate NSRange and four source files use it publicly. Decide and amend one side.~~ Fixed 2026-08-04 (`9ef3750`, `9d36811`, change `foundation-free-textrope` per ADR-013): the code moved — TextRope is Foundation-free with `Range<Int>` primitives, the NSRange surface lives in TextBuffer extensions, and the MUST-NOT clause is grep-checkably true.
- ~~`openspec/specs/rope-replace/spec.md:34,45` ("No insert/delete operation SHALL occur" in degenerate cases) is false as written — replace composes unconditionally; correctness rests on the primitives' undocumented pre-precondition early returns.~~ Fixed 2026-08-04 (same change, DEF-006b): the replace spec states observable equivalences (result equals `delete(in:)` / `insert(_:at:)` alone), pinned by equivalence tests.
- ~~`openspec/specs/rope-insert/spec.md:87,95` says an overflowing inner node splits "into two"; implementation is n-way.~~ Superseded during the train: the canonical insert spec now describes the n-way `splitInner`/sibling-batch behavior (promoted by `fix-rope-split-point` and `perf-rope-equality-and-bulk-insert`).
- ~~`m2-rope-delete` tasks 1.3/2.4 had the mandated `Node+Merge.swift` path rewritten to `TextRope+Delete.swift` inside fix commits `8e7ec0c`/`2abfd52` without disclosure (contrast the split seam, which got the spec-named `Node+Split.swift`).~~ Done 2026-08-03 (`6386e45`): merge machinery extracted to `Node+Merge.swift` as pure movement (DEF-006c).
- ~~All 11 promoted canonical specs still carry `## Purpose / TBD`.~~ Fixed 2026-08-03 (`3997670`, change `docs-rope-disclosure`).

### DEF-007: Stress suite validates invariants at 1% sampling — `fixed`

`TextRopeStressTests.swift:532,681`; `TextRopeInsertTests.swift:238`. `verifyTreeInvariants` runs every 100th op; DEF-001's manifestations are transient and slipped through 40,000 ops. Add at least one seed run validating every operation.

Fixed 2026-08-03 (`1e6a6aa`): `testPerOperationInvariantValidation` (seed `0xDEF007`, 2,000 ops, validated after every operation) alongside the four sampled 10k seeds, judged by the exact ADR-012 predicates (per-adjacent-leaf starvation, whole-cluster exception, unconditional seam check) — it caught a real producer gap on its first run. Sampled runs keep sampling with an explanatory comment.

### DEF-008: No concurrent-COW test on multi-level ropes — `fixed`

`SendableRopeBufferConcurrencyTests.testTaskGroupParallelReplace` fans 1000 parallel mutations over a single-leaf template, so concurrent path-copying below the root is never exercised. `TextRope: Sendable` (`nonisolated(unsafe) var root` over non-Sendable `Node`) rests entirely on the COW discipline this would verify. (Raised by ta2-speccer.)

Fixed 2026-08-03 (`46ee53f`): height-3 template (72×2047+`\n`, height pinned) exercised concurrently at rope level (`TextRopeConcurrentCOWTests`) and buffer level (`testTaskGroupParallelReplaceOnMultiLevelRope`); developer-local TSan run clean, invocation documented at the test.

### DEF-009: `expandingWindow` assumes returned window length equals requested — `fixed`

Fixed 2026-08-03 (`03ebba7`, change `fix-composed-sequence-reads`): the structural fix is ADR-012's grapheme-first chunk bounds, landed by `fix-rope-split-point` — a chunk seam can no longer fall inside a `Character`, so the desync is unreachable; the enforcing hard `precondition` on the materialized window length landed here.

`TextRope+ComposedSequences.swift:37-41`: `local` is computed assuming `content(in:)` returns exactly `windowEnd - windowStart` units; false when a chunk boundary falls mid-`Character` (the documented degenerate fallback at `Node+Split.swift:87-88`). Surrogate guards cover window edges only. Add a length assertion or handle the desync.

## Low

### DEF-010: `TextRope.==` materializes full content on mismatch — `fixed`

`TextRope.swift:39-43` reached from `SendableRopeBuffer.==`. TheArchive2's echo suppression compares content per edit event, making this a per-keystroke O(n) path. Consider summary-based early-out (utf8/utf16/lines mismatch ⇒ not equal) before materializing.

Fixed 2026-08-03 (`3f4b8e4`, change `perf-rope-equality-and-bulk-insert`): three-tier `==` with an O(1) root-summary early-out; soundness guarded by equal-summary/different-content tests. The equal-summary tier-3 path still materializes — allocation-free streaming comparison stays deferred pending a TheArchive2 profile.

### DEF-011: Read/insert performance regressions — `fixed`

- ~~`unsafeCharacter(at:)` ~5× slower post-`9570025` (window materialization + NSString bridge + two descents per call); no fast path for the common non-surrogate/non-mark case. Deferred — benchmark-driven.~~ Resolved 2026-08-04 (`fd7f2c0`, change `perf-read-fast-path`): conservative printable-ASCII simple-cluster fast path in `composedCharacterSequence(at:)` — one 3-unit block read; when the offset and both existing neighbors are in `0x20...0x7E`, the single-unit string is returned with no window materialization and no `NSString` bridge; anything else (including CR/LF) falls through to the windowed path unchanged. Measured (release, min-of-3, 20k-call batch): ASCII ~1 MiB per-call 1,492 → 289 ns (5.2× faster; vs `MutableStringBuffer` 10.52× → 2.81×); emoji-heavy and regional-indicator documents unchanged within variance (3,012 → 2,887 and 8,808 → 7,767 ns/call). Pinned by the `RopeReadPerformanceTests` size-independence ratio (1 MiB vs 4 MiB batch, measured 1.11×, bound 2×) and the mixed-content every-offset drift sweep.
- ~~Huge inserts into a non-root leaf are quadratic: repeated `splitLeaf` copies the whole tail each round (`TextRope+Insert.swift:37-44`); the root-leaf path already re-chunks in one pass — mirror it.~~ Resolved 2026-08-03: dissolved by `fix-rope-split-point`'s single-pass re-chunk; pinned linear by `3f4b8e4`'s perf-ratio test (1 MiB → 4 MiB ratio 4.01).

### DEF-012: `lineRange`/`wordRange` O(n) vs public large-document claim — `open` (docs half fixed; O(log n) queries deferred to M3)

Tagged `[M3 Rope Queries]` at `RopeBuffer.swift:44` and `TextAnalysisCapable.swift:46`, but the default `lineRange` at `TextAnalysisCapable.swift:51-55` (the one `SendableRopeBuffer` inherits) is untagged, and `RopeBuffer.swift:6-7` DocC still claims superiority for "very large documents" without caveat.

Docs half fixed 2026-08-03 (`8158875`, change `docs-rope-disclosure`): third marker on the inherited default; DocC recommendation scoped to editing with the materialization exception named on both rope buffers. The O(log n) implementations remain M3 Rope Queries.

### DEF-013: CHANGELOG 0.9.0 gaps — `fixed`

Fixed 2026-08-03 (`f657657`, change `docs-rope-disclosure`): the released 0.9.0 section amended in place with the Added section and seven Fixed disclosures; findLeaf fixes deliberately undisclosed.

No `Added` section: `RopeBuffer: CustomStringConvertible` (`98b5a35`) and the public composed-sequence API are undisclosed; the seven behavior-changing structural fixes are summarized as test work. Amend under the upcoming patch release notes.

### DEF-014: Test hygiene — `fixed`

- ~~`NodeTests.swift:42-48` pins DEF-001(4)'s buggy split point (fix together).~~ Fixed 2026-08-03 (`135457d`): reframed as the reasoned minimal-shortfall case, value asserted from ADR-012's reasoning.
- ~~`testDeleteLeafMergeDoesNotSplitCRLF` (`TextRopeDeleteTests.swift:306`) still executes no merge; `testDeleteSpanningLeaves` (`:108`) spans but never merges — rename or reshape.~~ Fixed 2026-08-03 (`135457d`): both reshaped so the merge genuinely fires; exact shapes asserted.
- ~~`testDeleteCausingLeafMerge` (`:130-131`) assertions don't discriminate merged from un-merged shapes; assert `[1050, 1050]`.~~ Fixed 2026-08-03 (`135457d`).
- ~~`testConsecutiveRoundTripsAreIdempotent` (`RopeTransferIntegrationTests.swift:126-143`) round-trips the same unmutated buffer thrice instead of chaining receiver into the next pass (spec `rope-transfer-convergence/spec.md:74-76`). Assigned to `fix-rope-cow-and-equality-coverage` per the 2026-08-01 decisions.~~ Fixed 2026-08-03 (`46ee53f`): each pass now chains the previous receiver; green on HEAD as predicted, plus redo/undo on the final receiver.
- `Node+Split.swift:71` doc comment misstates the fallback's trigger (fires on plain `\r\n` at width-1 windows, not just degenerate ZWJ chains) and omits the oversized-right-chunk residue.
- `RopeBufferDriftTests.swift:49` `MARK: - Delete` sits above the insert-with-selection tests.
