## Context

`TextRope.composedCharacterSequences(in:)` and `composedCharacterSequence(at:)` (`Sources/TextRope/TextRope+ComposedSequences.swift`) exist so `RopeBuffer.content(in:)` / `unsafeCharacter(at:)` can match `MutableStringBuffer`, which delegates to `NSString.rangeOfComposedCharacterSequence(s)` over the whole document. Materializing the whole rope per read would defeat the point of rope storage, so `expandingWindow` materializes a ±128 UTF-16 unit window, runs the `NSString` boundary search inside it, and retries with a doubled radius if the result touches a window edge:

```swift
let touchesLeadingEdge = expanded.location == 0 && windowStart > 0
let touchesTrailingEdge = expanded.location + expanded.length == window.length && windowEnd < utf16Count
if !touchesLeadingEdge && !touchesTrailingEdge { return window.substring(with: expanded) }
radius *= 2
```

The retry is the *entire* correctness argument for the windowing: "if the window truncated the answer, the answer touches the edge, so retry bigger." DEF-002 is the case where that argument fails. This change repairs the argument for the one Unicode rule that breaks it, and makes the window's implicit length assumption (DEF-009) explicit.

Scope is two source files: `TextRope+ComposedSequences.swift`, plus `TextRope+Navigation.swift` for the DEF-004 precondition move (see "Resolved open questions" below). `RopeBuffer` (`Sources/TextBuffer/Buffer/RopeBuffer.swift:49-62`) and `SendableRopeBuffer` (`:52-64`) both call straight through to the rope, so both inherit the fixes without edits.

## Goals / Non-Goals

**Goals:**
- Windowed composed reads produce, for every offset in every document, exactly what full-document `NSString` expansion produces — RI runs included
- The window length assumption is guaranteed structurally by ADR-012 and enforced with a hard `precondition` (DEF-009)
- Zero-length out-of-range reads trap like any other out-of-bounds read (DEF-004), with process-exit test coverage
- Regression coverage at the rope level and at the buffer-drift level, red before green
- The composed-read contract is written into the specs so the next behavior change cannot land untested

**Non-Goals:**
- Read-path performance work (DEF-011) — the RI walk is on the cold path; no fast path is added here
- Root-causing mid-scalar chunk splits (DEF-001) — fixed upstream by `fix-rope-split-point` under ADR-012; this change only enforces the resulting invariant
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

Rationale for the shape of the fallback rather than its constant: correctness must not depend on the cap. Any cap value yields correct results; the cap only chooses where the cost cliff sits. 2048 consecutive flags is not real prose, so the cliff is unreachable outside adversarial or generated input, and the fallback keeps such input *correct* rather than *fast*. The constant is fixed at 4,096 (resolved 2026-08-01): the cap bounds RI-run walking, which is a property of the text, not of chunk geometry, so it is deliberately not derived from `Node.maxChunkUTF8`. The fallback is silent — no `assertionFailure` in any build configuration — so tests can drive it as an ordinary path.

The cap is measured in UTF-16 units, not RI count, so it is comparable to `radius` and cheap to check against `windowStart`.

### D3: Why GB12/13 is the only window-breaking rule

The reviewer verified empirically that combining marks and ZWJ chains do not diverge (DEFECTS.md DEF-002: "Combining marks and ZWJ chains verified unaffected"). The structural reason, which the tests must pin so the verification does not decay:

Every other grapheme-cluster rule — GB9 (extend/ZWJ), GB9a (spacing marks), GB9b (prepend), GB11 (emoji ZWJ sequences), GB9c (Indic conjunct linkers) — is *locally decidable*: whether a break exists between two adjacent scalars depends only on scalars within the same cluster. So when a window cuts such a cluster, the truncated part of the cluster is at the window edge by construction, the expansion result touches that edge, and the existing retry fires and widens the window. Truncation is always *observable* at the edge.

GB12/13 is the sole rule with **unbounded, non-local left context**: the break decision at a point depends on the count (parity) of RI characters extending arbitrarily far to the left. A window can therefore start with a *complete, well-formed* RI cluster that is nonetheless the wrong cluster — the mispairing is invisible at the edges because nothing was truncated; the pairs are merely shifted by one RI. That is exactly why the retry never fires and why DEF-002 returns `"🇪🇩"` instead of `"🇩🇪"`.

This is the load-bearing argument of the whole design: the anchor walk restores "window context ≡ document context" for the one rule that violated it, leaving the edge-touch retry responsible for all the rest. Tests in section 1.3 of tasks.md pin the combining-mark/ZWJ half so a future rule change (or a Foundation behavior change) surfaces as a red test rather than as another silent content defect.

### D4: DEF-009 — `precondition` the window length

`expandingWindow` computes `local` as `NSRange(location: utf16Range.location - windowStart, length: utf16Range.length)`, valid only if `content(in:)` returned exactly `windowEnd - windowStart` UTF-16 units. Before `fix-rope-split-point`, that could fail when a chunk boundary fell mid-scalar via the then-documented degenerate fallback at `Node+Split.swift:87-88`, shifting the window underneath `local`: at best a wrong answer, at worst an `NSString` range exception. Under ADR-012's grapheme-first chunk bounds — established by `fix-rope-split-point`, after which this change sequences — a chunk seam can never fall inside a `Character`, so the desync is structurally unreachable.

Handling (resolved 2026-08-01, superseding this design's earlier debug-assert-plus-release-fallback shape): compare `window.length` against `windowEnd - windowStart` and `precondition` on mismatch, in all build configurations. A mismatch can only mean a broken rope-internal invariant, and no text computed against a shifted window is correct to return — so trapping beats any recovery, including in shipping apps. The release fallback and the desync test are dropped: the fallback would be dead code guarding an unreachable state, and the test cannot be written without faking tree state.

Deliberately not chosen: silently clamping `local` into the returned window (hides the defect and can still return wrong text), and the earlier assert-plus-fallback (launders an invariant break into a plausible-looking read in release). `precondition` was earlier rejected as "a crash on a read path in shipping apps" — that reasoning held only while the desync was reachable; with ADR-012 making it a can't-happen state, the crash is the correct surfacing of a corrupted rope.

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
- **[Trade-off] The DEF-009 `precondition` is untestable by construction** → under ADR-012 no reachable rope state desynchronizes the window, so the check ships without a covering test — it is an executable statement of the invariant, not a defended branch. Faking tree state to trigger it was rejected; ADR-012's tree validator owns the underlying invariant.

## Resolved open questions (2026-08-01)

- **DEF-009 disposition**: under ADR-012 (grapheme-first chunk bounds) a chunk seam can never fall inside a `Character`, so the window-length desync is structurally unreachable. The debug-assert-plus-fallback design (D4) is superseded: the length check becomes a hard `precondition`, the release fallback and the unreachable desync test are dropped. This change sequences after `fix-rope-split-point`, which establishes that invariant.
- **Window cap**: fixed at 4,096 UTF-16 units, not derived from `Node.maxChunkUTF8` — the cap bounds RI-run walking, which is a property of text, not of chunk geometry. Cap-exceeded falls back to full-document expansion silently (testable; no `assertionFailure`).
- **Capability placement**: the composed API stays under `rope-utf16-navigation`; revisit only if a future spec-map cleanup warrants its own capability.
- **Read fast path**: confirmed out of scope (DEF-011, deferred pending benchmarks).
- **Scope addition (DEF-004)**: this change also enforces the out-of-bounds trap for zero-length ranges — preconditions move before the empty-range early returns in `content(in:)` and both composed-sequence APIs, with exit tests for past-end, negative, and `NSNotFound` locations. Decided 2026-08-01; a 0.10.0-scope behavior tightening.
