## Context

`TextRope.composedCharacterSequences(in:)` and `composedCharacterSequence(at:)` (`Sources/TextRope/TextRope+ComposedSequences.swift`) exist so `RopeBuffer.content(in:)` / `unsafeCharacter(at:)` can match `MutableStringBuffer`, which delegates to `NSString.rangeOfComposedCharacterSequence(s)` over the whole document. Materializing the whole rope per read would defeat the point of rope storage, so `expandingWindow` materializes a ±128 UTF-16 unit window, runs the `NSString` boundary search inside it, and retries with a doubled radius if the result touches a window edge:

```swift
let touchesLeadingEdge = expanded.location == 0 && windowStart > 0
let touchesTrailingEdge = expanded.location + expanded.length == window.length && windowEnd < utf16Count
if !touchesLeadingEdge && !touchesTrailingEdge { return window.substring(with: expanded) }
radius *= 2
```

The retry is the *entire* correctness argument for the windowing: "if the window truncated the answer, the answer touches the edge, so retry bigger." DEF-002 is the case where that argument fails. This change repairs the argument for the one Unicode rule that breaks it, and makes the window's implicit length assumption (DEF-009) explicit.

Scope is a single file. `RopeBuffer` (`Sources/TextBuffer/Buffer/RopeBuffer.swift:49-62`) and `SendableRopeBuffer` (`:52-64`) both call straight through to the rope, so both inherit the fix without edits.

## Goals / Non-Goals

**Goals:**
- Windowed composed reads produce, for every offset in every document, exactly what full-document `NSString` expansion produces — RI runs included
- The window length assumption is either guaranteed or explicitly detected (DEF-009)
- Regression coverage at the rope level and at the buffer-drift level, red before green
- The composed-read contract is written into the specs so the next behavior change cannot land untested

**Non-Goals:**
- Read-path performance work (DEF-011) — the RI walk is on the cold path; no fast path is added here
- Root-causing mid-scalar chunk splits (DEF-001) — DEF-009 is contained, not cured
- Empty-range precondition bypass (DEF-004), even though it lives at `TextRope+ComposedSequences.swift:9`
- Any change to `RopeBuffer` / `SendableRopeBuffer` source

## Decisions

### D1: Parity anchor — snap `windowStart` back to the start of the contiguous RI run

UAX #29 GB12/GB13 read: *do not break between regional indicators if there are an odd number of RI characters before the break point*, where "before" counts back to the nearest non-RI character. Pairing therefore restarts at every maximal RI run boundary and nowhere else. The window is a correct context for the pairing iff its start is not strictly inside an RI run.

So: after the existing trail-surrogate adjustment, if `windowStart` sits inside an RI run, walk backward over `U+1F1E6...U+1F1FF` scalars until reaching a non-RI scalar or offset 0. That anchor is a run boundary, `NSString` restarts pairing there, and pairing inside the window matches pairing computed from document start.

Two properties make this the minimal fix:

- **Only the leading edge needs it.** GB12/13 context flows left-to-right from the run start; a run cut by the *trailing* edge yields an expansion result that touches that edge, so the existing retry handles it. `windowEnd` needs no change.
- **Snapping to the run start is not just sufficient, it's necessary.** Parity at an arbitrary interior offset is only knowable relative to the run start, so any "walk back to a parity-correct anchor" reduces to finding the run start anyway. There is no cheaper anchor.

Alternatives rejected:

- *Rely on radius doubling.* It cannot work. `windowStart = location - radius` with `radius ∈ {128, 256, 512, …}`, all ≡ 0 (mod 4); an RI is 2 UTF-16 units, so doubling preserves `windowStart`'s parity within the run. The window grows forever and stays wrong — and the loop does not even run, because the mispaired result sits strictly inside the window and touches no edge. (DEF-002's repro is an infinite class, not an off-by-one.)
- *Count RIs from document start via the summary tree.* Would need a per-node RI count in `Summary`, i.e. a new cached metric maintained through every insert/delete/split/merge, to fix a cold-path read. Rejected as wildly disproportionate.
- *Always materialize the full document.* Correct, and what `MutableStringBuffer` does, but it discards the reason `TextRope` exists and would make `unsafeCharacter(at:)` `O(n)` per keystroke.

### D2: Cap the backward walk at 4096 UTF-16 units, fall back to full materialization

The walk is unbounded in principle: a document that is one enormous RI run makes it `O(n)`, and it would be running *inside* the retry loop. Cap it at 4096 UTF-16 units (2048 consecutive regional indicators) measured from the pre-walk `windowStart`. If the run continues past the cap, abandon windowing for this call and compute the expansion over `content` (the full document) — trivially correct, since that is exactly the `MutableStringBuffer` path.

Rationale for the shape of the fallback rather than its constant: correctness must not depend on the cap. Any cap value yields correct results; the cap only chooses where the cost cliff sits. 2048 consecutive flags is not real prose, so the cliff is unreachable outside adversarial or generated input, and the fallback keeps such input *correct* rather than *fast*. The constant itself is an open question (proposal Q1/Q2).

The cap is measured in UTF-16 units, not RI count, so it is comparable to `radius` and cheap to check against `windowStart`.

### D3: Why GB12/13 is the only window-breaking rule

The reviewer verified empirically that combining marks and ZWJ chains do not diverge (DEFECTS.md DEF-002: "Combining marks and ZWJ chains verified unaffected"). The structural reason, which the tests must pin so the verification does not decay:

Every other grapheme-cluster rule — GB9 (extend/ZWJ), GB9a (spacing marks), GB9b (prepend), GB11 (emoji ZWJ sequences), GB9c (Indic conjunct linkers) — is *locally decidable*: whether a break exists between two adjacent scalars depends only on scalars within the same cluster. So when a window cuts such a cluster, the truncated part of the cluster is at the window edge by construction, the expansion result touches that edge, and the existing retry fires and widens the window. Truncation is always *observable* at the edge.

GB12/13 is the sole rule with **unbounded, non-local left context**: the break decision at a point depends on the count (parity) of RI characters extending arbitrarily far to the left. A window can therefore start with a *complete, well-formed* RI cluster that is nonetheless the wrong cluster — the mispairing is invisible at the edges because nothing was truncated; the pairs are merely shifted by one RI. That is exactly why the retry never fires and why DEF-002 returns `"🇪🇩"` instead of `"🇩🇪"`.

This is the load-bearing argument of the whole design: the anchor walk restores "window context ≡ document context" for the one rule that violated it, leaving the edge-touch retry responsible for all the rest. Tests in section 1.3 of tasks.md pin the combining-mark/ZWJ half so a future rule change (or a Foundation behavior change) surfaces as a red test rather than as another silent content defect.

### D4: DEF-009 — assert the window length, fall back on mismatch

`expandingWindow` computes `local` as `NSRange(location: utf16Range.location - windowStart, length: utf16Range.length)`, valid only if `content(in:)` returned exactly `windowEnd - windowStart` UTF-16 units. That holds unless a chunk boundary fell mid-scalar — reachable via the documented degenerate fallback at `Node+Split.swift:87-88`, where `splitPoint` returns a UTF-8 index that is not a scalar boundary, so re-materializing the chunk repairs the broken scalar into U+FFFD and changes the code-unit count. `local` then indexes a window that has shifted underneath it: at best a wrong answer, at worst an `NSString` range exception.

Handling: compare `window.length` against `windowEnd - windowStart`; on mismatch `assert` (debug trap, so fuzzing and the stress suite surface the underlying split defect loudly) and, in release, take the full-document path from D2. Full materialization goes through the same `content` accessor the buffer's `content` property uses, so the read stays *consistent with what the buffer reports* even while the tree is in the degenerate state.

Deliberately not chosen: silently clamping `local` into the returned window (hides the defect and can still return wrong text), or `precondition` (turns a rope-internal invariant break into a crash on a read path in shipping apps). If DEF-001 lands and proves the desync unreachable, promoting this to `precondition` is a follow-up (proposal Q3).

### D5: Test placement — rope level and buffer level, both

The defect is a `TextRope` defect but was found through `RopeBuffer`. Both layers get coverage:

- `Tests/TextRopeTests/TextRopeComposedSequencesTests.swift` (new) — the public composed API has **zero** direct tests today; unit-level scenarios including the exact offset arithmetic (radius 128, run start, parity) and the window-edge matrix
- `Tests/TextBufferTests/RopeBufferDriftTests.swift` — extends the existing `MARK: - Composed Character Sequence Reads` block (`:179-214`), reusing `assertContentInMatches`, which already asserts `RopeBuffer` *and* `SendableRopeBuffer` against `MutableStringBuffer` in one call. The drift sweep is the test that would have caught DEF-002 in the first place: every offset of a long RI run compared against the reference buffer.

The drift helper compares against `MutableStringBuffer` rather than hardcoded expectations, so the reference is Foundation itself and the tests stay honest across OS versions.

## Risks / Trade-offs

- **[Risk] Cold-path cost on flag-heavy text** → every read whose window edge lands inside an RI run now walks back to the run start. Bounded by the cap and by real run lengths (a few flags), and the walk is a scalar scan over already-materialized leaf data. Compounding with DEF-011's existing ~5× read regression is acknowledged, not addressed.
- **[Risk] Walk implemented via repeated `findLeaf` descents** → a naive backward walk that calls `findLeaf(utf16Offset:)` per code unit is `O(k log n)`. Mitigation: walk within the leaf's `chunk` and only re-descend at leaf boundaries, mirroring the existing `isTrailSurrogate(at:)` access pattern.
- **[Risk] Foundation's RI behavior is the oracle** → the tests assert equality with `MutableStringBuffer`, so a Foundation change moves both sides together and the drift tests stay green by construction. The rope-level tests use hardcoded `"🇩🇪"` expectations for the headline repro to keep at least one absolute anchor.
- **[Trade-off] Fallback makes pathological input `O(n)` per read** → accepted; correctness over throughput on input that does not occur in prose.
- **[Risk] DEF-009's fallback branch is hard to reach in a test** → it requires constructing a rope with a mid-scalar chunk split, which today needs the DEF-001 degenerate path. If it cannot be provoked without new internal seams, the branch ships assertion-only with the desync test marked as a documented gap rather than faking the state.

## Resolved open questions (2026-08-01)

- **DEF-009 disposition**: under ADR-012 (grapheme-first chunk bounds) a chunk seam can never fall inside a `Character`, so the window-length desync is structurally unreachable. The debug-assert-plus-fallback design (D4) is superseded: the length check becomes a hard `precondition`, the release fallback and the unreachable desync test are dropped. This change sequences after `fix-rope-split-point`, which establishes that invariant.
- **Window cap**: fixed at 4,096 UTF-16 units, not derived from `Node.maxChunkUTF8` — the cap bounds RI-run walking, which is a property of text, not of chunk geometry. Cap-exceeded falls back to full-document expansion silently (testable; no `assertionFailure`).
- **Capability placement**: the composed API stays under `rope-utf16-navigation`; revisit only if a future spec-map cleanup warrants its own capability.
- **Read fast path**: confirmed out of scope (DEF-011, deferred pending benchmarks).
- **Scope addition (DEF-004)**: this change also enforces the out-of-bounds trap for zero-length ranges — preconditions move before the empty-range early returns in `content(in:)` and both composed-sequence APIs, with exit tests for past-end, negative, and `NSNotFound` locations. Decided 2026-08-01; a 0.10.0-scope behavior tightening.
