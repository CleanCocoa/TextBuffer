## Context

DEF-012's open half: both text-analysis queries on rope-backed buffers cost O(n) per call because they materialize the whole document. The call-site survey:

| Call site | Today | Who hits it |
|---|---|---|
| `RopeBuffer.lineRange(for:)` (`RopeBuffer.swift:39-48`) | bounds guard, then `(self.content as NSString).lineRange(for:)` | `RopeBuffer` |
| `TextAnalysisCapable` default `wordRange(for:)` (`TextAnalysisCapable.swift:43-48`) | `computeWordRange(for:in:contentRange:)` over `self.content as NSString` | `RopeBuffer` **and** `SendableRopeBuffer` |
| `TextAnalysisCapable` default `lineRange(for:)` (`TextAnalysisCapable.swift:51-56`) | `(self.content as NSString).lineRange(for:)` | `SendableRopeBuffer` |

All three carry `TODO: [M3 Rope Queries]` markers (entrenched by `docs-rope-disclosure`, which also scoped the DocC large-document recommendation on both rope buffers to editing). This change implements the queries and lifts the disclosure.

The relevant precedent is `fix-composed-sequence-reads` + ADR-013's 2026-08-03 amendment: NSString-parity machinery lives as `TextRope` extensions in the **TextBuffer target** (where Foundation legitimately lives), built on the `package`-scoped `TextRope.utf16CodeUnits(in: Range<Int>)` primitive so it never descends the tree per code unit. `TextRope+ComposedSequences.swift` demonstrates both patterns this change reuses: the block-walk (`regionalIndicatorRunStart(before:cappedAt:)`, fixed-size block reads scanned in memory) and the edge-touch retry (`expandingWindow(around:_:)`, radius doubling whenever the expansion result touches a window edge).

## Goals / Non-Goals

**Goals:**

- `lineRange(for:)` and `wordRange(for:)` on `RopeBuffer` **and** `SendableRopeBuffer` cost O(log n + result length) per call — measurably size-independent on a many-short-lines document.
- Observation-identical results: for every buffer content and every in-bounds range, both queries return exactly what `MutableStringBuffer` returns for the same call; `BufferAccessFailure` bounds behavior unchanged.
- The three `[M3 Rope Queries]` markers and both DocC O(n) caveats are removed *because the cost is fixed*; DEF-012 flips to fully `fixed`.
- TextRope target stays Foundation-free (ADR-013): all new machinery lives in the TextBuffer target.

**Non-Goals:**

- No summary-guided line-number queries (line index ↔ UTF-16 offset). `Summary.lines` counts only `\n` bytes (`Sources/TextRope/Summary.swift:28`) — it cannot answer any query under the six-delimiter `NSString.lineRange(for:)` contract (CR, NEL, LS, PS lines are invisible to it), so it is **not usable for delimiter-parity descent**. A parity-correct line summary is a rope-internal redesign; explicitly out of scope, left for the rest of M3.
- No change to the `TextAnalysisCapable` defaults' implementation — `MutableStringBuffer` and `NSTextViewBuffer` keep them; only their now-obsolete markers go.
- No public API additions: the windowed query extensions are `internal` to the TextBuffer target (sole consumers are the two rope buffers); promotion to public API is a separate decision.
- No read fast path for `content(in:)` (DEF-011, deferred, benchmark-driven).

## Decisions

### D1: Placement — `TextRope` extensions in the TextBuffer target, NSRange in, NSRange out

Both queries are *defined as* NSString parity: `lineRange` quotes `NSString.lineRange(for:)`'s delimiter list in the protocol DocC (`TextAnalysisCapable.swift:19-29`), and `wordRange` is defined by `computeWordRange`'s `CharacterSet`-based classification. Per ADR-013's amendment, that machinery belongs in the TextBuffer target as `TextRope` extensions (the composed-sequence precedent), consuming `utf16CodeUnits(in:)` and `content(in: Range<Int>)`. New files: `Sources/TextBuffer/TextRope+LineRange.swift` and `Sources/TextBuffer/TextRope+WordRange.swift`, `internal` visibility.

### D2: `lineRange` — bidirectional block-walk from the range edges

Algorithm, matching `NSString.lineRange(for:)` semantics:

1. **Line start**: scan backward from `searchRange.location`, reading `utf16CodeUnits(in:)` in fixed-size blocks (128 units, mirroring `regionalIndicatorWalkBlockSize`) and scanning each block in memory. The line start is the position immediately after the nearest line-delimiter **end** at or before `location - 1`, or 0.
2. **Line end**: scan forward from `searchRange.endLocation` (from `endLocation - 1` when the range is non-empty, because a range ending just past a delimiter still belongs to that line per NSString) for the next delimiter, returning the position after its **end**, or `utf16Count`.
3. Delimiter set, longest match preferred: `\r\n` (CRLF, one delimiter), `\n` (LF), `\r` (CR), `U+0085` (NEL), `U+2028` (LS), `U+2029` (PS) — exactly the list the `TextAnalysisCapable` DocC quotes from Foundation.

CRLF longest-match is the sharp edge and gets explicit handling at every seam:

- **Backward scan**: a `\n` found at position `k` must check position `k-1` for `\r` — including when `k-1` falls in the *previous* block (fetch one more unit) — so the delimiter end is still `k+1` but a `location` sitting *between* `\r` and `\n` is recognized as inside a delimiter: NSString treats such a location as part of the line the CRLF terminates, and the parity tests pin this.
- **Forward scan**: a `\r` at the end of a block must peek at the next unit before deciding the delimiter ends (lone `\r` ends the line; `\r\n` extends it by one).
- **Chunk seams are invisible by construction**: `utf16CodeUnits(in:)` is defined as the flat UTF-16 slice regardless of leaf layout, and ADR-012 guarantees no `\r\n` is ever split across leaves anyway — but the algorithm must not rely on that; it handles CRLF at *block* boundaries, which are arbitrary.

Cost: two descents to seed plus O(line length / blockSize) additional descents — O(log n + line length). No cap: unlike the RI walk, the scan cannot be abandoned to a fallback (the fallback *is* the O(n) behavior being removed); the degenerate case is D6.

### D3: `Summary.lines` is not a shortcut

`Summary.of(_:)` counts `\n` bytes only. A descent guided by it would place line boundaries wrong for CR-only, NEL, LS, and PS documents and could not implement longest-match CRLF (a `\r\n` counts as one `\n`, but a lone `\r` counts as zero lines). Stated here so nobody "optimizes" the scan into a summary descent later without first fixing the summary itself — which is the out-of-scope rest of M3.

### D4: `wordRange` — windowed `computeWordRange`, not a reimplementation

Reuse `computeWordRange(for:in:contentRange:)` verbatim over a materialized window:

1. Start with a radius of 128 UTF-16 units around the search range; align window edges to scalar boundaries (a window edge may land on a trail surrogate — same adjustment `expandingWindow` performs). Materialize via `content(in:)`, bridge to `NSString`.
2. Call `computeWordRange(for: local, in: window, contentRange: windowLocalFullRange)` and map the result back by adding the window start.
3. **Retry conditions** (double the radius and loop):
   - the result touches the leading window edge while `windowStart > 0`, or the trailing edge while `windowEnd < utf16Count` — a word run may continue past the window;
   - the whitespace scan was **inconclusive**: `computeWordRange` fell back to returning `baseRange` (or clamped against the window's `contentRange` bounds) while the window does not cover the whole document — an all-whitespace window says nothing about whether a word exists just beyond it. This condition is the one `expandingWindow` does not need and this design adds; the whitespace-run drift tests exist to catch it.

Unlike the composed-sequence window, **no regional-indicator run anchoring is needed**: `CharacterSet` membership is per-scalar (`wordBoundary` classifies each scalar independently; RI scalars are symbols either way), so window placement cannot flip a classification the way it flips GB12/GB13 pairing parity. Scalar-aligned edges suffice.

Rejected alternative: reimplementing word classification scalar-by-scalar over `utf16CodeUnits(in:)`. `computeWordRange` has non-obvious behavior (whitespace trimming, closest-non-whitespace fallback, the empty-result-returns-baseRange rule) that `BufferWordRangeTests` pins for `MutableStringBuffer`; a parallel implementation would drift from it exactly the way DEF-002 drifted from NSString. One implementation, two call shapes (full document for string buffers, window for ropes).

### D5: Wiring — explicit overrides on both rope buffers

- `RopeBuffer.lineRange(for:)` keeps its bounds guard and delegates to the windowed extension; `RopeBuffer` gains a `wordRange(for:)` override (today it inherits the default).
- `SendableRopeBuffer` gains **both** overrides — this is the critical half DEF-012 flagged: it currently inherits the two O(n) defaults, and without explicit overrides it would keep them silently while `RopeBuffer` got fast. The drift tests assert both buffer types in the same test for exactly this reason.
- The `guard contains(range:) else throw BufferAccessFailure.outOfRange(...)` shape is copied unchanged from the existing methods: same error, same `requested`/`available` payload, thrown before any read — the protocol's documented contract.

### D6: Degenerate honesty — the claim is O(log n + result length)

A document with no line delimiters makes `lineRange` O(n) by necessity: the line **is** the document, and returning it requires scanning it. Likewise an all-whitespace document makes `wordRange`'s window double out to the full document. Every statement of the complexity — spec scenarios, DocC on both buffers, CHANGELOG — says **O(log n + result length)**, never bare "O(log n)", so the claim survives the degenerate inputs instead of recreating DEF-012's overclaim in a new shape.

### D7: Test strategy — parity is green-first, the ratio is the honest red

The current implementations are *correct* (they call the oracle itself), so parity drift tests across the zoo — CRLF straddling a chunk seam in a >4KiB multi-leaf document, NEL/LS/PS, delimiter-free documents, ranges at document start/end, zero-length ranges, a zero-length range between `\r` and `\n`, ranges spanning multiple lines, words with apostrophes/hyphens/emoji, whitespace runs — MUST pass before the implementation lands. Their job is to pin the contract so the windowed implementations cannot drift.

The red-first test is the **perf ratio**: per-call `lineRange`/`wordRange` time on a many-short-lines 1 MiB document vs a 4 MiB document, mirroring `testBulkInsertCostGrowsLinearlyWithInsertedLength`'s discipline (`TextRopeInsertTests.swift:394-416`: `ContinuousClock`, best-of-3 with warm-up, `XCTSkipIf` below the noise floor, ratio assertion with the failure modes named). O(n) materialization scales ≈4× with the document; a size-independent query scales ≈1×. Asserting ratio < 2.0 fails on current `main` and passes after — the honest red for a change whose observable *results* do not move.

## Risks / Trade-offs

- **[Risk] NSString `lineRange` edge semantics** — locations inside a CRLF, ranges ending exactly on a line start, zero-length ranges at document end, and a trailing delimiter-less last line are all places a hand-rolled scan can diverge from Foundation. Mitigation: the oracle-based drift zoo runs both rope buffers against `MutableStringBuffer` (which calls NSString directly), including the exact edge inputs; any divergence is a red test, not a shipped defect.
- **[Risk] `computeWordRange` window-relativity** — the helper takes `contentRange` and uses its bounds as "no boundary found" fallbacks; with a window, those fallbacks mean "ran off the window", which the retry conditions must treat as inconclusive, not as an answer. A missed retry condition returns a subtly wrong range near window edges. Mitigation: D4's explicit inconclusive-scan condition plus edge-placed drift cases (word runs and whitespace runs crossing the initial 128-unit radius).
- **[Risk] Perf-test flakiness on CI** — wall-clock ratio tests are noise-sensitive. Mitigation: same discipline as the accepted bulk-insert guard — best-of-3, warm-up, skip below a noise floor, a ratio bound (2.0) with ≈4× headroom to the failure mode. Droppable-if-unstable is on record for the precedent test; the same applies here.
- **[Risk] Window doubling worst case** — pathological inputs (huge single line, huge whitespace run) degrade to full materialization via repeated doubling, costing an extra log-factor of retries over the old single materialization. Accepted: it is the documented degenerate case (D6), bounded by O(result length) work per retry level, and unreachable for the editing workloads the rope targets.
- **[Trade-off] Two query implementations for `wordRange` call shapes** — the same `computeWordRange` runs full-document for string buffers and windowed for ropes; the window plumbing is new code that only rope buffers exercise. Accepted over the alternative (scalar-by-scalar reimplementation) because the classification logic itself stays single-sourced — the drift risk lives in window placement, which the zoo covers, not in classification.
- **[Trade-off] `internal` visibility for the extensions** — a future consumer wanting rope-level `lineRange` without a buffer must wait for a deliberate API promotion. Accepted: zero known consumers, and `package`/`internal`-first matches the `utf16CodeUnits(in:)` precedent.
