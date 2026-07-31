## MODIFIED Requirements

### Requirement: RopeBuffer content access operations
`RopeBuffer` SHALL provide `content(in:)` for range reads, `unsafeCharacter(at:)` for single-character access, and `lineRange(for:)` for line range queries — all operating on UTF-16 offsets via `NSRange`.

`content(in:)` and `unsafeCharacter(at:)` SHALL return **composed character sequences**, not raw UTF-16 substrings: the requested range is expanded to composed character sequence boundaries exactly as `NSString.rangeOfComposedCharacterSequences(for:)` / `NSString.rangeOfComposedCharacterSequence(at:)` would expand it over the whole document. For every buffer content and every in-bounds argument, the result MUST be identical to what `MutableStringBuffer` returns for the same call. This includes UAX #29 GB12/GB13 regional indicator pairing, which is counted from the start of the maximal regional indicator run and therefore MUST NOT be affected by any internal windowing the rope uses to avoid materializing the full document.

Range validation is unchanged: an out-of-range subrange SHALL throw `BufferAccessFailure.outOfRange` before any read is attempted.

#### Scenario: Content in valid subrange returns substring
- **WHEN** `content(in: NSRange(location: 1, length: 3))` is called on a buffer containing `"hello"`
- **THEN** the result SHALL be `"ell"`

#### Scenario: Content in out-of-range subrange throws
- **WHEN** `content(in: NSRange(location: 3, length: 10))` is called on a buffer with 5 characters
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown

#### Scenario: Range property reflects current content length
- **WHEN** content is inserted or deleted
- **THEN** the `range` property SHALL always equal `NSRange(location: 0, length: rope.utf16Count)`

#### Scenario: Subrange cutting a surrogate pair expands to the whole character
- **WHEN** `content(in:)` is called on `"a😀b"` with a range covering only one surrogate half of the emoji
- **THEN** the result SHALL contain the complete emoji, matching `MutableStringBuffer` for the same call

#### Scenario: Subrange cutting a combining mark expands to the whole sequence
- **WHEN** `content(in:)` is called on `"e\u{301}b"` with a range covering only the base character or only the combining mark
- **THEN** the result SHALL contain the complete composed sequence, matching `MutableStringBuffer` for the same call

#### Scenario: unsafeCharacter returns the composed sequence at any interior offset
- **WHEN** `unsafeCharacter(at:)` is called at any UTF-16 offset inside a multi-unit composed sequence (surrogate half, combining mark, ZWJ chain member)
- **THEN** the result SHALL be the complete composed sequence containing that offset, matching `MutableStringBuffer` for the same offset

#### Scenario: Reads inside a regional indicator run are correctly paired
- **WHEN** a buffer holds `String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)` and `unsafeCharacter(at: 130)` is called
- **THEN** the result SHALL be `"🇩🇪"`, matching `MutableStringBuffer`
- **AND** it SHALL NOT be the mispaired `"🇪🇩"`

#### Scenario: Reads are independent of document position
- **WHEN** the same composed sequence appears near the start of a document and far beyond any internal read-window radius
- **THEN** reads at the corresponding offsets SHALL return the same string in both positions
