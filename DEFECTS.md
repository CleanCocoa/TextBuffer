# Defect Tracker

Open defects against 0.9.1 (`5cf2638`; found at 0.9.0 by the 2026-07-29 four-agent review of the M2 gap-closure fold `0.8.2..0.9.0` — the 0.9.1 delta touches only the NSTextView bridge, so all line references remain valid). All repros verified against a green suite — none of these are covered by existing tests. Target: upcoming patch release.

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
| DEF-011 (read fast path) | Deferred — benchmark-driven; interacts with `fix-composed-sequence-reads` |
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

### DEF-005: `TextRope: Equatable` has zero tests — `fixed`

`TextRope.swift:39`. Archived task `2026-07-29-m2-rope-foundation/tasks.md:36` is ticked naming Equatable coverage in `TextRopeConstructionTests.swift`; no rope-to-rope equality assertion exists anywhere. Spec: `openspec/specs/rope-core-types/spec.md:102-113`.

Fixed 2026-08-03 (`46ee53f`): `TextRopeEqualityTests.swift` covers the six spec cases, including equal-content/different-shape (leaf shapes asserted to differ) and equal-summary/different-content; the archived task's tick carries a disclosed correction note.

### DEF-006: Canonical spec contradictions and silent task rewrites — `open`

- `openspec/specs/rope-target-setup/spec.md:7` says TextRope "MUST NOT depend on ... Foundation's NSRange"; three sibling canonical specs mandate NSRange and four source files use it publicly. Decide and amend one side.
- `openspec/specs/rope-replace/spec.md:34,45` ("No insert/delete operation SHALL occur" in degenerate cases) is false as written — replace composes unconditionally; correctness rests on the primitives' undocumented pre-precondition early returns.
- `openspec/specs/rope-insert/spec.md:87,95` says an overflowing inner node splits "into two"; implementation is n-way.
- ~~`m2-rope-delete` tasks 1.3/2.4 had the mandated `Node+Merge.swift` path rewritten to `TextRope+Delete.swift` inside fix commits `8e7ec0c`/`2abfd52` without disclosure (contrast the split seam, which got the spec-named `Node+Split.swift`).~~ Done 2026-08-03 (`6386e45`): merge machinery extracted to `Node+Merge.swift` as pure movement (DEF-006c).
- All 11 promoted canonical specs still carry `## Purpose / TBD`.

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

### DEF-011: Read/insert performance regressions — `open` (read half only)

- `unsafeCharacter(at:)` ~5× slower post-`9570025` (window materialization + NSString bridge + two descents per call); no fast path for the common non-surrogate/non-mark case. Deferred — benchmark-driven.
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
