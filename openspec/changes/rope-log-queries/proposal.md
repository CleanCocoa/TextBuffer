## Why

DEF-012's remaining half. `RopeBuffer`'s public pitch is O(log n) editing for very large documents, yet both text-analysis queries materialize the **full document on every call** (`self.content as NSString`), making them O(n) in document length:

- `RopeBuffer.lineRange(for:)` (`Sources/TextBuffer/Buffer/RopeBuffer.swift:39-48`) overrides the protocol default but still materializes; `wordRange(for:)` falls through to the protocol default.
- The `TextAnalysisCapable` defaults (`Sources/TextBuffer/Buffer/TextAnalysisCapable.swift:41-57`) materialize via `computeWordRange(for:in:contentRange:)` and `NSString.lineRange(for:)` — and `SendableRopeBuffer` inherits **both** of them.

The `docs-rope-disclosure` change closed the honesty half in 0.10.0: three `TODO: [M3 Rope Queries]` markers sit at the materializing call sites, and the DocC on `RopeBuffer` and `SendableRopeBuffer` scopes the large-document recommendation to editing with the O(n)-queries exception named. This change pulls the "[M3 Rope Queries]" milestone work forward to close the performance half: implement windowed, rope-descending queries so the markers and caveats come off because the cost is fixed, not re-worded. DEF-012 then flips to fully `fixed`.

## What Changes

- **Windowed `lineRange`** — a `TextRope` extension in the TextBuffer target (Foundation is legitimate there per ADR-013's 2026-08-03 amendment, the placement precedent for NSString-parity machinery). Descend once to the search range's edges, then scan backward from `location` for the nearest line-delimiter end and forward from the range end for the next line end, reading `utf16CodeUnits(in:)` blocks — one descent per block, mirroring `regionalIndicatorRunStart`'s block-walk in `Sources/TextBuffer/TextRope+ComposedSequences.swift`. Delimiters match `NSString.lineRange(for:)` exactly: LF, CR, CRLF (longest match preferred), NEL `U+0085`, LS `U+2028`, PS `U+2029`. Cost: O(log n + line length). Note `Summary.lines` counts only `\n` bytes (`Sources/TextRope/Summary.swift`) and is **not** usable for delimiter-parity descent; summary-guided line-number queries stay out of scope.
- **Windowed `wordRange`** — reuse the existing NSString-based `computeWordRange` semantics (`Sources/TextBuffer/Buffer/Buffer+wordRange.swift`) over a materialized **window** instead of the whole document, with edge-touch retry/doubling exactly like `expandingWindow` in `TextRope+ComposedSequences.swift`: a word run (or inconclusive whitespace scan) touching the window edge doubles the radius. Cost: O(log n + word length). Rejected alternative: reimplementing word classification scalar-by-scalar — drift risk against `computeWordRange`.
- **Wire-up on both rope buffers** — `RopeBuffer.lineRange`/`wordRange` route to the windowed queries, and — critically — `SendableRopeBuffer` gains explicit overrides for **both** (today it silently inherits the O(n) defaults). Behavior is observation-identical: for every in-bounds range the result equals the full-document `NSString`/`computeWordRange` answer, and the throwing `BufferAccessFailure` bounds behavior stays exactly as the protocol requires.
- **Honest complexity statement** — a document with no line delimiters makes `lineRange` O(n) by necessity: the line *is* the document. The claim is therefore **O(log n + result length)** everywhere it appears (spec, DocC, CHANGELOG), never bare "O(log n)".
- **Red-first perf guard** — parity drift tests across a delimiter/word zoo are expected green-first (the current O(n) implementations are *correct*, just slow); the honest red is the ratio test: per-call query time on a many-short-lines 1 MiB vs 4 MiB document must not scale with document size, mirroring `testBulkInsertCostGrowsLinearlyWithInsertedLength`'s discipline (`Tests/TextRopeTests/TextRopeInsertTests.swift:394-416`). That ratio test MUST fail against current `main`, where O(n) materialization scales ≈4×.
- **Docs lift** — the three `[M3 Rope Queries]` TODO markers are removed with the implementations; the DocC O(n)-queries caveats on `RopeBuffer` (`RopeBuffer.swift:4-9`) and `SendableRopeBuffer` (`SendableRopeBuffer.swift:12-14`) update to the new complexity statement; DEF-012 flips to fully `fixed`.

No public API shape changes: both queries keep their `TextAnalysisCapable` signatures and their `MutableStringBuffer`-matching results — only the cost moves.

## Capabilities

### New Capabilities

- `rope-queries`: windowed `lineRange(for:)`/`wordRange(for:)` on rope-backed buffers — NSString-parity contract (results identical to full-document `NSString.lineRange(for:)`/`computeWordRange` semantics for every in-bounds range), the delimiter set spelled out, O(log n + result length) cost with a measurable size-independence scenario, and the unchanged throwing bounds behavior.

### Modified Capabilities

- `rope-buffer-conformance`: the "RopeBuffer conforms to TextAnalysisCapable" requirement — added by `docs-rope-disclosure` to entrench the O(n) disclosure and `[M3 Rope Queries]` markers — inverts: the queries no longer materialize the full document, the documentation states O(log n + result length), and a search for the marker finds nothing.
- `rope-buffer-drift`: adds drift requirements for both queries across the delimiter/word zoo, asserted for `RopeBuffer` **and** `SendableRopeBuffer` against the `MutableStringBuffer` oracle in the same tests.

## Impact

- **Sequencing:** depends on `foundation-free-textrope` (archived 2026-08-04): the queries live as `TextRope` extensions in the TextBuffer target and consume the `package`-scoped `utf16CodeUnits(in: Range<Int>)` primitive that change introduced. No open change touches these files.
- **New source:** `Sources/TextBuffer/TextRope+LineRange.swift`, `Sources/TextBuffer/TextRope+WordRange.swift` (windowed query machinery beside `TextRope+ComposedSequences.swift`).
- **Modified source:** `Sources/TextBuffer/Buffer/RopeBuffer.swift` (windowed `lineRange`, new `wordRange` override, marker removal, DocC lift); `Sources/TextBuffer/Buffer/SendableRopeBuffer.swift` (new `lineRange`/`wordRange` overrides, DocC lift); `Sources/TextBuffer/Buffer/TextAnalysisCapable.swift` (marker removal only — the defaults keep materializing, which is fine for `MutableStringBuffer`/`NSTextViewBuffer`, whose `content` bridging is not O(n)-per-query in the same sense and which no rope buffer inherits anymore).
- **Modified test files:** `Tests/TextBufferTests/RopeBufferDriftTests.swift` (new text-analysis drift block); new `Tests/TextBufferTests/RopeBufferQueryPerformanceTests.swift` (the red-first ratio tests).
- **Defect closed:** DEF-012 (fully — the docs half was closed by `docs-rope-disclosure` in 0.10.0).
- **Behavior change:** none observable in results or thrown errors; per-call cost of both queries on rope-backed buffers drops from O(n) to O(log n + result length).
- **Not addressed here:** summary-guided line-*number* queries (line index ↔ offset); `Summary.lines` counts only `\n` and cannot serve the six-delimiter parity contract. That remains future M3 work with its own design. DEF-011's read fast path also stays deferred (benchmark-driven).
