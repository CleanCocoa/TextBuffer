## ADDED Requirements

### Requirement: Drift tests prove text-analysis query equivalence with MutableStringBuffer

For every text-analysis scenario, calling `lineRange(for:)` or `wordRange(for:)` on a `RopeBuffer` and on a `SendableRopeBuffer` holding the same content SHALL return exactly what `MutableStringBuffer` returns for the same call. The drift tests SHALL compare against `MutableStringBuffer` (Foundation as the oracle) rather than hardcoded expectations, and both rope-backed buffer types MUST be asserted in the same test — `SendableRopeBuffer` previously inherited a different (full-document default) implementation than `RopeBuffer`, so single-type coverage would leave the other free to drift.

#### Scenario: Line delimiter zoo

- **WHEN** documents delimited by `\n`, `\r`, `\r\n`, `U+0085` (NEL), `U+2028` (LS), and `U+2029` (PS) — and a document mixing them — are queried via `lineRange(for:)` with zero-length ranges at delimiter-adjacent offsets, ranges inside a line, and ranges spanning multiple lines
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: CRLF straddling a chunk seam

- **WHEN** both rope buffer kinds hold an identical document larger than 4 KiB (so the rope has multiple leaves) with CRLF pairs placed near leaf boundaries, and `lineRange(for:)` queries force the scan across those seams — including a zero-length range between a `\r` and its `\n`
- **THEN** every result SHALL equal the `MutableStringBuffer` result for the same range

#### Scenario: Line queries at document edges

- **WHEN** `lineRange(for:)` is called with ranges at the document start, the zero-length range at the document end, a range ending exactly on a line start, a final line without a terminator, and on a delimiter-free document
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: Word zoo

- **WHEN** `wordRange(for:)` is called on words with apostrophes and hyphens, emoji words, emoji adjacent to letters, and a word longer than 256 UTF-16 units, with zero-length ranges at word starts, ends, and interiors
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: Whitespace runs

- **WHEN** `wordRange(for:)` is called with ranges inside whitespace runs — including a run whose nearest word lies hundreds of UTF-16 units away, and an all-whitespace document
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: Out-of-bounds queries throw identically

- **WHEN** `lineRange(for:)` and `wordRange(for:)` are called with a range past the document end, a negative location, and `NSNotFound`
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL throw `BufferAccessFailure.outOfRange` exactly where `MutableStringBuffer` throws it
