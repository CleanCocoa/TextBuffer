# rope-queries Specification

## Purpose
TBD - created by archiving change rope-log-queries. Update Purpose after archive.
## Requirements
### Requirement: Windowed lineRange matches full-document NSString semantics

`lineRange(for:)` on rope-backed buffers (`RopeBuffer` and `SendableRopeBuffer`) SHALL NOT materialize the full document. For every buffer content and every in-bounds search range, the result MUST be identical to `NSString.lineRange(for:)` evaluated over the full document — the queries read only windows around the search range via rope descent, and the windowing MUST NOT be observable in any result.

Line delimiters are exactly Foundation's set, the longest possible sequence preferred to any shorter:

- `U+000A` LINE FEED (`\n`)
- `U+000D` CARRIAGE RETURN (`\r`)
- `U+0085` NEXT LINE (NEL)
- `U+2028` LINE SEPARATOR
- `U+2029` PARAGRAPH SEPARATOR
- `\r\n` (CRLF), treated as a single delimiter

#### Scenario: Line expansion across every delimiter kind

- **WHEN** documents delimited by `\n`, `\r`, `\r\n`, `U+0085`, `U+2028`, and `U+2029` — and a document mixing them — are queried with zero-length and multi-line-spanning ranges
- **THEN** every result SHALL equal `NSString.lineRange(for:)` over the full document for the same range

#### Scenario: CRLF is one delimiter, longest match preferred

- **WHEN** `lineRange(for:)` is called with a zero-length range located between the `\r` and `\n` of a CRLF pair
- **THEN** the result SHALL treat the CRLF as a single delimiter, identical to `NSString.lineRange(for:)` for the same location

#### Scenario: CRLF straddling an internal chunk seam

- **WHEN** a document larger than 4 KiB (so the rope holds multiple leaves) places CRLF pairs near leaf boundaries and queries force the line scan across those seams
- **THEN** every result SHALL equal the full-document `NSString.lineRange(for:)` answer — internal chunk layout MUST NOT be observable

#### Scenario: Document edges and terminator-less last line

- **WHEN** `lineRange(for:)` is called with ranges at the document start, at the document end (including the zero-length range at `utf16Count`), and on a final line that has no terminating delimiter
- **THEN** every result SHALL equal `NSString.lineRange(for:)` over the full document

#### Scenario: Delimiter-free document

- **WHEN** `lineRange(for:)` is called on a document containing no line delimiters
- **THEN** the result SHALL be the whole document range, identical to `NSString.lineRange(for:)`

### Requirement: Windowed wordRange matches full-document word semantics

`wordRange(for:)` on rope-backed buffers (`RopeBuffer` and `SendableRopeBuffer`) SHALL NOT materialize the full document. For every buffer content and every in-bounds search range, the result MUST be identical to the `TextAnalysisCapable` default implementation's full-document `computeWordRange` answer (the `MutableStringBuffer` behavior). The implementation SHALL reuse the same word classification as the full-document path over a materialized window, retrying with a larger window whenever a result touches a window edge or a whitespace scan is inconclusive — a window boundary MUST NOT be observable in any result.

#### Scenario: Word interior punctuation and emoji

- **WHEN** `wordRange(for:)` is called on words containing apostrophes and hyphens, on emoji words, and on emoji adjacent to letters
- **THEN** every result SHALL equal `MutableStringBuffer.wordRange(for:)` for the same content and range

#### Scenario: Word run crossing the initial window radius

- **WHEN** a word longer than the initial window radius surrounds the search range
- **THEN** the result SHALL cover the whole word, identical to `MutableStringBuffer` — the window doubles until the word fits

#### Scenario: Whitespace runs wider than the window

- **WHEN** the search range sits inside a whitespace run whose nearest word lies beyond the initial window radius
- **THEN** the result SHALL equal `MutableStringBuffer.wordRange(for:)` — an all-whitespace window is treated as inconclusive, not as an answer

#### Scenario: Zero-length ranges and document edges

- **WHEN** `wordRange(for:)` is called with zero-length ranges at word starts, ends, and interiors, and with ranges at the document start and end
- **THEN** every result SHALL equal `MutableStringBuffer.wordRange(for:)` for the same call

### Requirement: Query cost is O(log n + result length)

`lineRange(for:)` and `wordRange(for:)` on rope-backed buffers SHALL cost O(log n + result length) per call: rope descents to the search range's neighborhood plus work proportional to the returned range, never work proportional to document length. The complexity claim SHALL be stated as O(log n + result length) — not bare O(log n) — wherever it appears (specs, documentation, changelog): a document with no line delimiters makes the line *be* the document, and returning it costs O(result length) by necessity.

#### Scenario: Per-call time is independent of document size

- **WHEN** the same mid-document `lineRange(for:)` or `wordRange(for:)` query runs on a many-short-lines document of 1 MiB and on an equivalent document of 4 MiB
- **THEN** the per-call time SHALL NOT scale with document size — the measured ratio stays well below the ≈4× that full-document materialization exhibits

#### Scenario: Degenerate result spans the document

- **WHEN** `lineRange(for:)` runs on a delimiter-free document, or `wordRange(for:)` runs on an all-whitespace document
- **THEN** the call MAY cost O(document length) — the result length is the document length — and the result SHALL still equal the full-document oracle answer

### Requirement: Bounds behavior is unchanged by windowing

Both queries on both rope-backed buffer types SHALL validate the search range against the buffer's `range` and throw `BufferAccessFailure.outOfRange` — with the same `requested`/`available` payload as today — before any read is attempted. The windowed implementations MUST NOT change which inputs throw.

#### Scenario: Out-of-range line query throws

- **WHEN** `lineRange(for:)` is called on a `RopeBuffer` or `SendableRopeBuffer` with a range past the document end, a negative location, or `NSNotFound`
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown, identical to the pre-windowing behavior

#### Scenario: Out-of-range word query throws

- **WHEN** `wordRange(for:)` is called on a `RopeBuffer` or `SendableRopeBuffer` with a range past the document end, a negative location, or `NSNotFound`
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown, identical to the pre-windowing behavior

