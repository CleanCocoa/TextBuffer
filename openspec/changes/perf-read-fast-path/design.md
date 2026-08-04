## Context

Since ADR-013's Foundation-free split, the composed-sequence read machinery lives in the TextBuffer target: `Sources/TextBuffer/TextRope+ComposedSequences.swift` extends `TextRope` with `composedCharacterSequence(at:)` and `composedCharacterSequences(in:)`, reading rope content exclusively through the stdlib-only accessors `content(in:)`, `utf16Count`, and the `package`-scoped `utf16CodeUnits(in:)` (`Sources/TextRope/TextRope+Navigation.swift:80`) — callable from TextBuffer because both targets share the package (swift-tools-version 6.2).

Anatomy of one `composedCharacterSequence(at: k)` call today, all inside `expandingWindow`:

1. `scalarAlignedStart(at:)` — one block read of up to 3 code units (tree descent).
2. `isTrailSurrogate(at:)` — one block read of 1 code unit (tree descent).
3. `content(in:)` over the ±128-unit window — O(log n + 256) extraction into a fresh `String`.
4. Bridge to `NSString`, run `rangeOfComposedCharacterSequence(at:)`, plus the DEF-009 length precondition and edge-touch checks.
5. `substring(with:)` back out.

Every step is per-call **constant** (the window radius is fixed; only the descents carry an O(log n) factor), but the constant is heavy: measured ~5× slower than `MutableStringBuffer.unsafeCharacter(at:)`, which does one `rangeOfComposedCharacterSequence` on an already-materialized `NSMutableString`. For a printable-ASCII read with printable-ASCII neighbors — the dominant case in code and prose — the entire window-and-bridge apparatus computes a result that three code units already determine.

Relevant precedents this change follows:

- `perf-rope-equality-and-bulk-insert` — the perf-change template: ratio test with min-of-N timing, warm-up, `XCTSkipIf` noise floor, and a bound placed far from both the good and bad cost models (`testBulkInsertCostGrowsLinearlyWithInsertedLength`, `Tests/TextRopeTests/TextRopeInsertTests.swift:397`); measured numbers recorded in the archived tasks.md.
- `fix-composed-sequence-reads` — the composed-read template: drift sweeps against the `MutableStringBuffer` oracle at every offset, both rope buffer kinds asserted in the same test.
- `TextRopeStressTests` — the summary-`print` precedent for reporting measurements through the test log without asserting them.

## Goals / Non-Goals

**Goals:**

- Remove the window-materialization and `NSString`-bridge cost from `composedCharacterSequence(at:)` for reads where three code units provably determine the answer — near-parity with `MutableStringBuffer` on ASCII documents.
- Zero observable behavior change: the fast path returns exactly what the windowed path (and the full-document `NSString` expansion it matches) returns, at every offset of every document.
- Close DEF-011's read half with in-repo benchmarks: a size-independence regression pin and a recorded before/after comparative measurement.
- Pin fast-path/slow-path agreement with an every-offset mixed-content drift sweep that exercises the triple check's conservatism at every boundary.

**Non-Goals:**

- **`composedCharacterSequences(in:)` and `content(in:)` (the range forms) keep the windowed path unconditionally.** Their cost structure is different: the dominant term is extraction and boundary expansion of a caller-chosen span, not a fixed window constant around a single offset, and `content(in:)` must materialize the span regardless. A fast path there would be speculative — measure first, and only if a consumer profile shows the range form hot on ASCII spans. This change's benchmarks cover the point read only.
- DEF-012's O(log n) `lineRange`/`wordRange` (M3 Rope Queries).
- Any change to the regional-indicator run anchoring, the 4,096-unit walk cap, the silent full-document fallback, or the DEF-009 window-length precondition — `expandingWindow` and its helpers are untouched.
- Widening the safe set beyond printable ASCII (see D1's rejected alternatives).
- Caching, cursors, or any state carried between reads — both rope buffers rely on `TextRope`'s value semantics, and `SendableRopeBuffer` on its `Sendable` conformance.

## Decisions

### D1: The safe set is printable ASCII `0x20...0x7E`, and a triple check suffices for parity

The fast path fires only when the code units at `k-1`, `k`, and `k+1` (those that exist) are **all** in `0x20...0x7E`. Sufficiency argument for `NSString` parity:

- The current unit is a complete scalar — printable ASCII contains no surrogate halves, so `String(UnicodeScalar(current))` is well-formed and equals the one-unit substring at `k`.
- The composed sequence at `k` cannot extend **rightward**: extension requires the next scalar to be a combining mark, ZWJ, variation selector, emoji modifier, or the LF of a CRLF pair — all outside printable ASCII, so the `k+1` check excludes them.
- It cannot extend **leftward**: the previous scalar would have to bind to the current one, and no printable-ASCII pair forms a single composed sequence — among ASCII only CR×LF binds (GB3), and both are controls outside the safe set. Prepend-class characters, regional indicators, and every other cross-boundary binder are non-ASCII (regional indicators are non-BMP surrogate pairs, so GB12/GB13 run parity is unreachable from a safe triple by construction).
- A **missing neighbor is safe**: document start and end are unconditional boundaries (GB1/GB2), so at `k = 0` or `k = utf16Count - 1` the absent side cannot bind.

Therefore `rangeOfComposedCharacterSequence(at: k)` over the full document is exactly `{k, 1}`, and the fast path's answer equals the full-document expansion — the same contract the windowed path satisfies. The check inspects **three** units even though the common intuition is "current is ASCII, done": the neighbor checks are what carry the parity proof (a combining mark after, or a cluster continuing across `k`, is only excluded by looking at the neighbors).

**Rejected — wider safe sets.** All BMP non-combining scalars, or "ASCII plus Latin-1", would need Unicode property tables (Extend, ZWJ, SpacingMark, Prepend, InCB for GB9c) that must then track Unicode versions and match whatever `NSString` links against. Printable ASCII needs no tables, is provably closed under the argument above, and covers the case the regression is actually felt in. The safe set is a floor, not a ceiling — widening it later is a compatible change, but it must bring its own parity proof.

### D2: CR and LF are excluded — the fast path never adjudicates the CRLF divergence

`\r\n` is a single Swift grapheme cluster, and whether `rangeOfComposedCharacterSequence` splits it is precisely the pinned divergence point between Swift grapheme semantics and Darwin `NSString` semantics: the canonical `rope-utf16-navigation` spec pins `"\r"` — not `"\r\n"` — at the `\r` offset of `"a\r\nb"`, and Foundation implementations across platforms have not historically agreed (the drift suite runs cross-platform by spec, with `MutableStringBuffer` as the per-platform oracle). A fast path that answered `"\r"` or `"\n"` from the unit alone would silently take a side in that divergence; one that answered for a printable character *next to* a CR without checking would miss that CRLF can form one composed sequence under grapheme-derived implementations. Excluding all controls — CR, LF, TAB, everything below `0x20`, plus DEL at `0x7F` — routes every CR/LF-adjacent read through the same `NSString` call the oracle uses on each platform, so parity holds by construction wherever the suite runs, and the fast path only claims territory where the answer is platform-invariant.

### D3: One block read of at most three code units, no Foundation

The probe is a single `utf16CodeUnits(in: max(0, utf16Offset - 1) ..< min(utf16Count, utf16Offset + 2))` — one tree descent returning at most three units (fewer at document edges), the same shape `scalarAlignedStart(at:)` already uses. The current unit's index in the block is `utf16Offset == 0 ? 0 : 1`. On the fast path the result is built with `String(UnicodeScalar(_:))` — stdlib only; no `content(in:)`, no `NSString`, no window. On fall-through, the block's cost is three code units and one descent, a small fraction of the windowed path it precedes, so the slow path's regression is bounded and the existing behavior is otherwise byte-for-byte unchanged. The guard sits **after** the existing bounds `precondition` so out-of-bounds offsets keep trapping identically.

**Rejected — reusing the probe inside `expandingWindow`.** Threading the three units into `scalarAlignedStart` to save its later block read would entangle the fast path with the window machinery this change deliberately leaves untouched; the fall-through cases are the rare ones, and one extra 3-unit descent there is noise.

### D4: Scope is the point read only

`unsafeCharacter(at:)` is the API the ~5× regression was filed against and the one consumers call per keystroke; it maps 1:1 onto `composedCharacterSequence(at:)`. The range forms stay out (Non-Goals) — different cost structure, no measured need. The buffers (`RopeBuffer.swift:62`, `SendableRopeBuffer.swift:66`) need no edits; both inherit the fast path through the rope extension.

### D5: Benchmarks — what is red-first, what is a pin, what is a report

Three instruments, with honesty about their colors:

1. **Size-independence ratio test** (`RopeReadPerformanceTests`, asserted): total time for a fixed number of `unsafeCharacter(at:)` calls at offsets spread across a 1 MiB ASCII document versus a 4 MiB one; assert the ratio is well under the ≈4× that document-proportional work would predict (bound 2×, generous against the ≈1× constant-cost and ≈1.1× log-descent models). Tolerance discipline mirrors `testBulkInsertCostGrowsLinearlyWithInsertedLength`: min-of-3 timing per size, a warm-up round, and `XCTSkipIf` when the baseline is below a milliseconds-scale noise floor, so CI jitter skips rather than flakes. **This test is expected to pass on current `main`** — the fixed ±128 window makes today's cost per-call constant already — and the tasks say so. It is the permanent regression pin the fast-path requirement's performance scenario points at, not the red test.
2. **Comparative measurement** (same file, reported, never asserted): per-call time for rope-backed `unsafeCharacter(at:)` versus `MutableStringBuffer.unsafeCharacter(at:)` on identical ASCII, emoji-heavy, and regional-indicator documents, printed to the test log in the `TextRopeStressTests` summary-print style. This is where the defect is visible — ~5× on ASCII before, near-parity expected after — and where closing it is demonstrated. Cross-implementation wall-clock ratios are not hard-asserted: two different implementations' constants vary across machines and toolchains in ways that would make any threshold either meaningless or flaky. The before/after numbers are recorded in tasks.md's verification step and the CHANGELOG entry, following the DEF-011 insert-half precedent (`perf-rope-equality-and-bulk-insert` recorded its measured 4.01× in its archived tasks).
3. **Every-offset mixed sweep** (drift suite, asserted, green-first): the correctness net, deliberately landed *before* the implementation so it demonstrably pins the windowed path's behavior, then holds the fast path to it.

**Rejected — an instrumentation hook counting descents or window materializations.** It would make "at most one block read" directly assertable, but adds test-only API surface to `TextRope` (or a hook type in the read path) for a property the ratio test already bounds observably. The spec states the block-read bound normatively; the ratio test is its measurable scenario.

## Risks / Trade-offs

- **A parity bug in the fast path is a silent wrong-content bug** — exactly the DEF-002 class. → Mitigation: the safe set is provably closed (D1), the every-offset mixed sweep compares both rope buffers against the oracle at every fast/slow boundary including CRLF and ASCII-adjacent-to-non-ASCII offsets, and all existing drift sweeps (RI runs, cap fallback, ZWJ/combining far-offset pins) stay as-is.
- **Future widening of the safe set without re-proving parity.** The constant `0x20...0x7E` invites "harmless" extension. → Mitigation: the spec delta names the safe set and the fall-through conditions normatively; any widening is a spec change that must re-argue D1, and the mixed sweep catches locally-wrong widenings.
- **Wall-clock ratio flakiness on shared CI.** → Mitigation: the same discipline that has kept the insert ratio test stable — min-of-N, warm-up, noise-floor skip, a bound far from both cost models — and the correctness of the change never rests on the timing test.
- **Divergent maintenance: two code paths answer the same question.** → Mitigation: the fast path is ~10 lines guarding a single early return, states its parity argument in a comment pointing at the spec requirement, and the windowed path remains the sole authority for everything outside the safe set.
- **The comparative report could rot into noise nobody reads.** → Mitigation: it exists to close the deferral with recorded numbers (tasks.md, CHANGELOG); ongoing regression protection is the asserted ratio pin, not the report.

## Open Questions

1. **Should the range form get the same treatment?** Out of scope here (Non-Goals). If a consumer profile shows `content(in:)`/`composedCharacterSequences(in:)` hot on all-ASCII spans, a fast path that checks the span's boundary units (interior units cannot affect the expansion of the endpoints) is the natural follow-up — with its own change and its own parity argument.
2. **Is 2× the right ratio bound?** It is generous against both honest models (constant ≈1×, log-descent ≈1.1×) and far from document-proportional ≈4×. If CI shows skips or near-misses, the bound can loosen toward 3× without losing discriminating power; the task notes the knob.
