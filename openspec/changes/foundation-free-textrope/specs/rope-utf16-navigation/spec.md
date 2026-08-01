## MODIFIED Requirements

### Requirement: Content extraction by UTF-16 range

`TextRope` SHALL provide a public `content(in utf16Range: Range<Int>) -> String` method that returns the substring corresponding to the given half-open range of UTF-16 code unit offsets. The extraction MUST be O(log n + k) where k is the length of the extracted content. The range MUST be validated before any early return: `utf16Range.lowerBound >= 0` and `utf16Range.upperBound <= utf16Count` MUST hold, or a precondition failure occurs — including for empty ranges whose bounds lie outside the document.

#### Scenario: Range within a single leaf
- **WHEN** `content(in:)` is called with a range that falls entirely within one leaf
- **THEN** the method MUST return the correct substring from that leaf's chunk

#### Scenario: Range spanning multiple leaves
- **WHEN** `content(in:)` is called with a range that spans two or more leaves
- **THEN** the method MUST concatenate the suffix of the first leaf, the full content of any intermediate leaves, and the prefix of the last leaf, returning the correct combined substring

#### Scenario: Empty range
- **WHEN** `content(in: k..<k)` is called where `0 <= k <= utf16Count`
- **THEN** the method MUST return an empty string `""`

#### Scenario: Empty range out of bounds
- **WHEN** `content(in: k..<k)` is called where `k > utf16Count` or `k < 0`
- **THEN** a precondition failure MUST occur

#### Scenario: Full document range
- **WHEN** `content(in: 0..<utf16Count)` is called
- **THEN** the method MUST return a string equal to the rope's `content` property

#### Scenario: Range at document boundaries
- **WHEN** `content(in:)` is called with a range starting at offset 0 or ending at `utf16Count`
- **THEN** the method MUST correctly handle these boundary positions without error

#### Scenario: Range with multi-byte and surrogate pair characters
- **WHEN** `content(in:)` is called with a range that includes emoji (surrogate pairs), accented characters, or CJK characters
- **THEN** the extracted content MUST be character-correct, with UTF-16 offsets properly resolved to character boundaries

#### Scenario: Content extraction on empty rope
- **WHEN** `content(in: 0..<0)` is called on an empty `TextRope`
- **THEN** the method MUST return `""`

#### Scenario: Range exceeds document bounds
- **WHEN** `content(in:)` is called with a range where `upperBound > utf16Count`
- **THEN** a precondition failure MUST occur

### Requirement: Composed character sequence reads match full-document NSString semantics

The `TextBuffer` target SHALL provide, as public extensions on `TextRope`, `composedCharacterSequences(in utf16Range: NSRange) -> String` and `composedCharacterSequence(at utf16Offset: Int) -> String`. These APIs are deliberately homed in the TextBuffer target rather than the Foundation-free `TextRope` target because their contract is defined by Foundation: for every rope and every in-bounds argument, the returned string MUST be identical to the result of applying `NSString.rangeOfComposedCharacterSequences(for:)` / `NSString.rangeOfComposedCharacterSequence(at:)` to the rope's **entire** content and extracting the resulting range. The result MUST NOT depend on the rope's internal chunking, tree shape, or on any window size used internally to avoid materializing the whole document. The implementation MUST access rope content exclusively through `TextRope`'s public stdlib-only primitives (`content(in:)`, `utf16CodeUnits(in:)`, `utf16Count`).

#### Scenario: Read equals full-document expansion at every offset
- **WHEN** `composedCharacterSequence(at: k)` is called for any `k` in `0..<utf16Count`
- **THEN** the result SHALL equal `(rope.content as NSString).substring(with: (rope.content as NSString).rangeOfComposedCharacterSequence(at: k))`

#### Scenario: Read is independent of tree shape
- **WHEN** two ropes hold identical content but were built differently (single leaf versus many leaves, e.g. via bulk init versus incremental inserts)
- **THEN** `composedCharacterSequence(at: k)` SHALL return the same string from both for every `k`

#### Scenario: Surrogate pair halves resolve to the whole character
- **WHEN** `composedCharacterSequence(at:)` is called at either the lead or the trail surrogate offset of a non-BMP character such as 😀
- **THEN** the result SHALL be the complete character

#### Scenario: Combining mark sequences are returned whole
- **WHEN** the rope contains base-plus-combining-mark sequences (e.g. `e\u{301}`) and a read targets the base or the mark offset
- **THEN** the result SHALL be the complete composed sequence

#### Scenario: ZWJ emoji chains are returned whole
- **WHEN** the rope contains a ZWJ emoji sequence (e.g. 👨‍👩‍👧‍👦) and a read targets any offset inside it
- **THEN** the result SHALL be the complete sequence, regardless of how far into the document the sequence sits

#### Scenario: NSString semantics are preserved where they diverge from Swift graphemes
- **WHEN** the rope contains `"a\r\nb"` and `composedCharacterSequence(at:)` is called at the offset of the `\r`
- **THEN** the result SHALL be `"\r"` — the NSString composed sequence — not the Swift grapheme cluster `"\r\n"`

#### Scenario: Composed reads available without importing Foundation-facing rope API separately
- **WHEN** a module imports only `TextBuffer` and holds a `TextRope`
- **THEN** both composed-sequence methods are callable on it

## ADDED Requirements

### Requirement: Code unit extraction by UTF-16 range

`TextRope` SHALL provide a public `utf16CodeUnits(in utf16Range: Range<Int>) -> [UTF16.CodeUnit]` method returning the UTF-16 code units of the rope's content within the given half-open offset range, equal to the corresponding slice of `content`'s `utf16` view. The extraction MUST be O(log n + k) where k is the range length. Unlike `content(in:)`, the range boundaries carry **no** character- or scalar-alignment requirement: a range that begins or ends between the two halves of a surrogate pair MUST return the raw unpaired code units. The range MUST satisfy `lowerBound >= 0` and `upperBound <= utf16Count`, or a precondition failure occurs.

#### Scenario: Code units match the content's UTF-16 view
- **WHEN** `utf16CodeUnits(in: a..<b)` is called on a rope with mixed ASCII, multi-byte, and emoji content
- **THEN** the result SHALL equal `Array(rope.content.utf16)[a..<b]`

#### Scenario: Mid-surrogate range returns raw halves
- **WHEN** a rope contains `"a🎉b"` (UTF-16: `a`, high surrogate, low surrogate, `b`) and `utf16CodeUnits(in: 2..<4)` is called
- **THEN** the result SHALL be the low surrogate of 🎉 followed by the code unit for `b`, with no substitution or expansion

#### Scenario: Range spanning multiple leaves
- **WHEN** the requested range spans two or more leaves of a multi-leaf rope
- **THEN** the returned code units SHALL be the correct concatenation across leaf boundaries

#### Scenario: Empty range
- **WHEN** `utf16CodeUnits(in: k..<k)` is called where `0 <= k <= utf16Count`
- **THEN** the result SHALL be an empty array

#### Scenario: Out-of-bounds range traps
- **WHEN** `utf16CodeUnits(in:)` is called with `lowerBound < 0` or `upperBound > utf16Count`
- **THEN** a precondition failure MUST occur
