# rope-buffer-conformance Specification

## Purpose
Makes `RopeBuffer` a drop-in `Buffer` implementation: a class wrapping `TextRope` with selection tracking whose insert, delete, and replace adjust the selection exactly as `MutableStringBuffer` does, whose `content(in:)` and `unsafeCharacter(at:)` return composed character sequences identical to `MutableStringBuffer`'s `NSString`-backed results (including regional-indicator pairing unaffected by internal windowing), and whose range validation, `modifying` gate, and `TextAnalysisCapable` conformance match the string buffer — so consumers can swap buffer implementations without behavior change.

## Requirements
### Requirement: RopeBuffer conforms to Buffer protocol
`RopeBuffer` SHALL be a `public final class` conforming to `Buffer` with `Range == NSRange` and `Content == String`. It SHALL wrap a `TextRope` instance for storage and maintain a `selectedRange: NSRange` property for selection tracking.

#### Scenario: Empty initialization
- **WHEN** a `RopeBuffer` is created with `RopeBuffer()`
- **THEN** its `content` SHALL be an empty string
- **AND** its `range` SHALL be `NSRange(location: 0, length: 0)`
- **AND** its `selectedRange` SHALL be `NSRange(location: 0, length: 0)`

#### Scenario: Initialization with content
- **WHEN** a `RopeBuffer` is created with `RopeBuffer("hello")`
- **THEN** its `content` SHALL be `"hello"`
- **AND** its `range` SHALL be `NSRange(location: 0, length: 5)`
- **AND** its `selectedRange` SHALL be `NSRange(location: 0, length: 0)` (insertion point at beginning)

#### Scenario: Content reflects rope UTF-16 length
- **WHEN** a `RopeBuffer` is initialized with a string containing multi-byte characters (e.g., `"café"`)
- **THEN** its `range.length` SHALL equal the UTF-16 code unit count of the string

### Requirement: RopeBuffer insert delegates to TextRope and adjusts selection
`RopeBuffer.insert(_:at:)` SHALL insert content into the wrapped `TextRope` at the given UTF-16 offset and adjust `selectedRange` using the same logic as `MutableStringBuffer`.

#### Scenario: Insert before insertion point shifts selection right
- **WHEN** `selectedRange` is `{5, 0}` and `insert("XX", at: 2)` is called
- **THEN** the text SHALL contain `"XX"` at offset 2
- **AND** `selectedRange` SHALL be `{7, 0}` (shifted right by 2)

#### Scenario: Insert at insertion point shifts selection right
- **WHEN** `selectedRange` is `{5, 0}` and `insert("XX", at: 5)` is called
- **THEN** `selectedRange` SHALL be `{7, 0}` (shifted right by 2)

#### Scenario: Insert after insertion point does not shift selection
- **WHEN** `selectedRange` is `{5, 0}` and `insert("XX", at: 7)` is called
- **THEN** `selectedRange` SHALL remain `{5, 0}`

#### Scenario: Insert before selection shifts entire selection right
- **WHEN** `selectedRange` is `{5, 3}` and `insert("XX", at: 2)` is called
- **THEN** `selectedRange` SHALL be `{7, 3}` (location shifted, length preserved)

#### Scenario: Insert at out-of-range location throws
- **WHEN** `insert("X", at: 100)` is called on a buffer with 5 characters
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown

### Requirement: RopeBuffer delete delegates to TextRope and adjusts selection
`RopeBuffer.delete(in:)` SHALL delete the specified UTF-16 range from the wrapped `TextRope` and adjust `selectedRange` by subtracting the deleted range using the same logic as `MutableStringBuffer`.

#### Scenario: Delete before insertion point shifts selection left
- **WHEN** `selectedRange` is `{5, 0}` and `delete(in: {1, 2})` is called
- **THEN** `selectedRange` SHALL be `{3, 0}`

#### Scenario: Delete after insertion point does not shift selection
- **WHEN** `selectedRange` is `{5, 0}` and `delete(in: {7, 2})` is called
- **THEN** `selectedRange` SHALL remain `{5, 0}`

#### Scenario: Delete across insertion point collapses to deletion start
- **WHEN** `selectedRange` is `{5, 0}` and `delete(in: {3, 4})` is called
- **THEN** `selectedRange` SHALL be `{3, 0}`

#### Scenario: Delete encompassing selection collapses selection
- **WHEN** `selectedRange` is `{4, 2}` and `delete(in: {2, 6})` is called
- **THEN** `selectedRange` SHALL be `{2, 0}`

#### Scenario: Delete at out-of-range throws
- **WHEN** `delete(in: {8, 5})` is called on a buffer with 10 characters
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown

### Requirement: RopeBuffer replace delegates to TextRope and adjusts selection
`RopeBuffer.replace(range:with:)` SHALL replace the specified UTF-16 range in the wrapped `TextRope` with new content and adjust `selectedRange` by first subtracting the replaced range, then shifting by the inserted content length — identical to `MutableStringBuffer`.

#### Scenario: Replace before selection shifts selection
- **WHEN** `selectedRange` is `{6, 0}` and `replace(range: {1, 3}, with: "XXXXX")` is called
- **THEN** `selectedRange` SHALL be `{8, 0}` (subtract 3 from shift, add 5 for new content)

#### Scenario: Replace at out-of-range throws
- **WHEN** `replace(range: {8, 5}, with: "X")` is called on a buffer with 10 characters
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown

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

#### Scenario: Reads over a flag run longer than the rope's internal cap
- **WHEN** a buffer holds more than 2,048 consecutive regional indicators (a contiguous run exceeding the rope's fixed 4,096-UTF-16-unit backward-walk cap) and reads target offsets inside the run
- **THEN** the results SHALL match `MutableStringBuffer` for the same calls
- **AND** no assertion or trap SHALL fire in any build configuration — the rope falls back silently to full-document expansion

### Requirement: RopeBuffer conforms to TextAnalysisCapable
`RopeBuffer` SHALL conform to `TextAnalysisCapable`, providing `lineRange(for:)` and inheriting the default `wordRange(for:)` implementation from the protocol extension.

#### Scenario: lineRange expands to full line
- **WHEN** `lineRange(for: NSRange(location: 7, length: 0))` is called on a buffer containing `"hello\nworld"`
- **THEN** the result SHALL be `NSRange(location: 6, length: 5)` (the `"world"` line)

#### Scenario: lineRange for out-of-range throws
- **WHEN** `lineRange(for: NSRange(location: 20, length: 0))` is called on a buffer with 10 characters
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown

### Requirement: RopeBuffer modifying gate
`RopeBuffer.modifying(affectedRange:_:)` SHALL validate the range and execute the block, matching `MutableStringBuffer` behavior.

#### Scenario: Valid range executes block
- **WHEN** `modifying(affectedRange: validRange) { 42 }` is called
- **THEN** the block SHALL execute and return `42`

#### Scenario: Invalid range throws without executing block
- **WHEN** `modifying(affectedRange: outOfRange) { ... }` is called
- **THEN** a `BufferAccessFailure.outOfRange` error SHALL be thrown
- **AND** the block SHALL NOT execute

