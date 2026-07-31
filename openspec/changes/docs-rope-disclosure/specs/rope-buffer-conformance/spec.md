## MODIFIED Requirements

### Requirement: RopeBuffer conforms to TextAnalysisCapable
`RopeBuffer` SHALL conform to `TextAnalysisCapable`, providing `lineRange(for:)` and inheriting the default `wordRange(for:)` implementation from the protocol extension.

Both text-analysis operations currently materialize the full document content on every call (`self.content as NSString`), making them O(n) in document length regardless of the rope's O(log n) mutation characteristics. The public documentation of `RopeBuffer` SHALL disclose this caveat and SHALL scope any large-document recommendation to the mutation operations (insert, delete, replace) rather than claiming unqualified superiority over `MutableStringBuffer`. Every full-document-materializing text-analysis call site — including the default `lineRange(for:)` that `SendableRopeBuffer` inherits — SHALL carry the `[M3 Rope Queries]` marker until summary-guided rope traversal replaces it.

#### Scenario: lineRange expands to full line
- **WHEN** `lineRange(for: NSRange(location: 7, length: 0))` is called on a buffer containing `"hello\nworld"`
- **THEN** the result SHALL be `NSRange(location: 6, length: 5)` (the `"world"` line)

#### Scenario: lineRange for out-of-range throws
- **WHEN** `lineRange(for: NSRange(location: 20, length: 0))` is called on a buffer with 10 characters
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown

#### Scenario: Documented performance caveat
- **WHEN** a reader consults the public documentation of `RopeBuffer`
- **THEN** the documentation SHALL state that `lineRange(for:)` and `wordRange(for:)` materialize the full document on each call
- **AND** the large-document recommendation SHALL name the operations it applies to (insert, delete, replace)

#### Scenario: Materializing call sites are marked
- **WHEN** the sources are searched for `[M3 Rope Queries]`
- **THEN** every text-analysis implementation that reads `self.content` in full SHALL be found, including the default `lineRange(for:)` in `TextAnalysisCapable` inherited by `SendableRopeBuffer`
