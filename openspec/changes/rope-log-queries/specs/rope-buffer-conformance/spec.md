## MODIFIED Requirements

### Requirement: RopeBuffer conforms to TextAnalysisCapable

`RopeBuffer` SHALL conform to `TextAnalysisCapable`, providing its own `lineRange(for:)` and `wordRange(for:)` implementations backed by windowed rope reads.

Neither text-analysis operation materializes the full document: both cost O(log n + result length) per call — rope descents to the search range's neighborhood plus work proportional to the returned range (a delimiter-free document degenerately makes the line the whole document). Results are unchanged from the previous full-document implementations: for every in-bounds range, `lineRange(for:)` equals `NSString.lineRange(for:)` over the full document and `wordRange(for:)` equals the `TextAnalysisCapable` default's `computeWordRange` answer (see the `rope-queries` capability for the normative query contract). The public documentation of `RopeBuffer` SHALL state the O(log n + result length) complexity for the queries, and the large-document recommendation no longer needs a text-analysis exception. The `[M3 Rope Queries]` markers that flagged the former full-document-materializing call sites are removed together with those call sites.

#### Scenario: lineRange expands to full line

- **WHEN** `lineRange(for: NSRange(location: 7, length: 0))` is called on a buffer containing `"hello\nworld"`
- **THEN** the result SHALL be `NSRange(location: 6, length: 5)` (the `"world"` line)

#### Scenario: lineRange for out-of-range throws

- **WHEN** `lineRange(for: NSRange(location: 20, length: 0))` is called on a buffer with 10 characters
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown

#### Scenario: Documented performance caveat

- **WHEN** a reader consults the public documentation of `RopeBuffer`
- **THEN** the documentation SHALL state that `lineRange(for:)` and `wordRange(for:)` cost O(log n + result length) via windowed rope reads
- **AND** it SHALL NOT claim bare O(log n) for the queries — the degenerate delimiter-free document, whose line is the whole document, is covered by the result-length term

#### Scenario: Materializing call sites are marked

- **WHEN** the sources are searched for `[M3 Rope Queries]`
- **THEN** no marker SHALL be found — every formerly marked full-document-materializing text-analysis call site, including the `TextAnalysisCapable` defaults previously inherited by `SendableRopeBuffer`, has been replaced by (or no longer serves) a rope-backed buffer
