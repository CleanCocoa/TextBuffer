## ADDED Requirements

### Requirement: Drift tests prove mixed-content every-offset point-read equivalence

The drift suite SHALL sweep `unsafeCharacter(at:)` at **every** UTF-16 offset of a single document that interleaves printable ASCII with emoji (surrogate pairs), combining marks, ZWJ chains, CRLF line breaks, and regional indicator runs — each non-ASCII feature bracketed by ASCII on both sides — comparing `RopeBuffer` and `SendableRopeBuffer` against `MutableStringBuffer` at every offset. The existing read-drift requirements each sweep a single feature per document and cover no CRLF reads; this combined sweep exists so that every boundary between a simple ASCII context and a complex cluster context — the offsets where a read implementation must decide between a cheap local answer and full composed-sequence expansion — is pinned against the Foundation-backed oracle, and a divergence introduced by any internal read specialization surfaces as a failing drift test rather than a silent content defect.

#### Scenario: Every offset of a mixed-content document
- **WHEN** both rope buffer kinds and a `MutableStringBuffer` hold a document interleaving ASCII prose with 😀, `e\u{301}`, a ZWJ emoji chain, `\r\n` pairs, a regional indicator run, and a lone regional indicator, and `unsafeCharacter(at:)` is called at every UTF-16 offset
- **THEN** every result from `RopeBuffer` and `SendableRopeBuffer` SHALL equal the `MutableStringBuffer` result at that offset

#### Scenario: ASCII offsets adjacent to non-ASCII content
- **WHEN** reads target printable ASCII units that sit immediately before or after a non-ASCII feature — including a single ASCII character wedged between two non-ASCII features, and the ASCII characters directly surrounding a `\r\n` pair
- **THEN** every result SHALL equal the `MutableStringBuffer` result at that offset

#### Scenario: CRLF offsets match the oracle
- **WHEN** `unsafeCharacter(at:)` is called at the `\r` offset and at the `\n` offset of a `\r\n` pair inside the mixed document
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return exactly what `MutableStringBuffer` returns at those offsets, whatever the platform's `NSString` answers

#### Scenario: Document edges of a mixed document
- **WHEN** the swept document starts and ends with non-ASCII content, and additionally an all-ASCII document is swept at offset `0` and its final offset
- **THEN** every result SHALL equal the `MutableStringBuffer` result at that offset
