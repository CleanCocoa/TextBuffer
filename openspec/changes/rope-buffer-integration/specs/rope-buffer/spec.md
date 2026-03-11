## ADDED Requirements

### Requirement: RopeBuffer conforms to Buffer
`RopeBuffer` SHALL be a `final class` conforming to `Buffer` with `Range == NSRange` and `Content == String`. It SHALL wrap a `TextRope` instance and a `selectedRange: NSRange` property. It SHALL be `@MainActor`-isolated, matching every other `Buffer` conformer.

#### Scenario: Empty initialisation
- **WHEN** `RopeBuffer()` is created with no arguments
- **THEN** `content` is `""`, `range` is `NSRange(location: 0, length: 0)`, `selectedRange` is `NSRange(location: 0, length: 0)`

#### Scenario: Content initialisation
- **WHEN** `RopeBuffer("hello")` is created
- **THEN** `content` is `"hello"` and `range.length` equals `"hello".utf16.count`

#### Scenario: content(in:) returns correct substring
- **WHEN** `content(in: NSRange(location: 1, length: 3))` is called on a buffer containing `"hello"`
- **THEN** the result is `"ell"`

#### Scenario: content(in:) throws on out-of-range
- **WHEN** `content(in:)` is called with a range that exceeds the buffer length
- **THEN** it throws `BufferAccessFailure`

#### Scenario: unsafeCharacter(at:) returns single character
- **WHEN** `unsafeCharacter(at: 0)` is called on a buffer containing `"hi"`
- **THEN** the result is `"h"`

---

### Requirement: RopeBuffer insert adjusts selection
`RopeBuffer.insert(_:at:)` SHALL delegate to `TextRope.insert` and then adjust `selectedRange` using the same rules as `MutableStringBuffer`:
- If the insertion point is before or exactly at `selectedRange.location`: shift `selectedRange.location` right by the UTF-16 length of the inserted string.
- If the insertion point is within the selected range but after `selectedRange.location`, or strictly after the selection, do not adjust `selectedRange.location`. 

#### Scenario: Insert before selection shifts cursor right
- **WHEN** `selectedRange` is `NSRange(location: 5, length: 0)` and `insert("ab", at: 2)` is called
- **THEN** `selectedRange.location` becomes `7`

#### Scenario: Insert after selection does not move cursor
- **WHEN** `selectedRange` is `NSRange(location: 3, length: 0)` and `insert("xy", at: 5)` is called
- **THEN** `selectedRange` is unchanged

#### Scenario: Insert at selection start with range selection does not collapse selection
- **WHEN** `selectedRange` is `NSRange(location: 3, length: 4)` and `insert("x", at: 3)` is called
- **THEN** `selectedRange.location` becomes `4` and `selectedRange.length` remains `4`

---

### Requirement: RopeBuffer delete adjusts selection
`RopeBuffer.delete(in:)` SHALL delegate to `TextRope.delete` and then adjust `selectedRange` identically to `MutableStringBuffer`: if the deleted range overlaps or precedes the selection, clamp and subtract the deleted length from `selectedRange.location` and/or `selectedRange.length` as appropriate; if the deletion fully swallows the selection, collapse `selectedRange` to the deletion start.

#### Scenario: Delete before selection shifts cursor left
- **WHEN** `selectedRange` is `NSRange(location: 6, length: 0)` and `delete(in: NSRange(location: 1, length: 2))` is called
- **THEN** `selectedRange.location` becomes `4`

#### Scenario: Delete overlapping selection shrinks selection
- **WHEN** `selectedRange` is `NSRange(location: 3, length: 5)` and `delete(in: NSRange(location: 4, length: 2))` is called
- **THEN** `selectedRange` is `NSRange(location: 3, length: 3)`

#### Scenario: Delete swallowing selection collapses to deletion start
- **WHEN** `selectedRange` is `NSRange(location: 3, length: 2)` and `delete(in: NSRange(location: 2, length: 6))` is called
- **THEN** `selectedRange` is `NSRange(location: 2, length: 0)`

#### Scenario: Delete entirely after selection does not move cursor
- **WHEN** `selectedRange` is `NSRange(location: 1, length: 2)` and `delete(in: NSRange(location: 5, length: 3))` is called
- **THEN** `selectedRange` is unchanged

---

### Requirement: RopeBuffer replace adjusts selection
`RopeBuffer.replace(range:with:)` SHALL delegate to `TextRope.replace` and apply the same selection adjustment as `MutableStringBuffer`: equivalent to delete-then-insert, applied in sequence.

#### Scenario: Replace shorter — selection after replace point shifts left
- **WHEN** `selectedRange` is `NSRange(location: 8, length: 0)` and `replace(range: NSRange(location: 2, length: 4), with: "x")` is called (net change: −3)
- **THEN** `selectedRange.location` becomes `5`

#### Scenario: Replace longer — selection after replace point shifts right
- **WHEN** `selectedRange` is `NSRange(location: 5, length: 0)` and `replace(range: NSRange(location: 1, length: 2), with: "abcde")` is called (net change: +3)
- **THEN** `selectedRange.location` becomes `8`

---

### Requirement: RopeBuffer conforms to TextAnalysisCapable
`RopeBuffer` SHALL conform to `TextAnalysisCapable`. Because `RopeBuffer` has `Range == NSRange` and `Content == String`, it SHALL use the existing default implementations of `wordRange(for:)` and `lineRange(for:)`, which operate via `content`. No rope-native analysis is required in this change.

#### Scenario: lineRange(for:) matches String-backed behavior
- **WHEN** `lineRange(for:)` is called on a `RopeBuffer`
- **THEN** the returned range matches the result that `MutableStringBuffer` would produce for the same content and search range

#### Scenario: wordRange(for:) matches String-backed behavior
- **WHEN** `wordRange(for:)` is called on a `RopeBuffer`
- **THEN** the returned range matches the result that `MutableStringBuffer` would produce for the same content and search range

---

### Requirement: RopeBuffer is behaviourally equivalent to MutableStringBuffer
For any sequence of `insert`, `delete`, `replace`, and `selectedRange` assignments, `RopeBuffer` and `MutableStringBuffer` started from the same initial state SHALL produce identical `content` and `selectedRange` values after every step. This equivalence is verified by the drift test suite (`RopeBufferDriftTests`).

#### Scenario: Insert sequence produces identical content and selection
- **WHEN** the same sequence of `insert` calls is applied to both a `RopeBuffer` and a `MutableStringBuffer` starting from the same initial content and selection
- **THEN** after each call, `content` and `selectedRange` are identical on both buffers

#### Scenario: Mixed insert/delete/replace sequence produces identical state
- **WHEN** an interleaved sequence of `insert`, `delete`, and `replace` calls is applied to both buffer types
- **THEN** `content` and `selectedRange` remain identical after every step

#### Scenario: Large document random-operation sequence produces no drift
- **WHEN** 500+ random insert/delete/replace operations are applied to both buffer types seeded from the same random source
- **THEN** no content or selection mismatch occurs at any step
