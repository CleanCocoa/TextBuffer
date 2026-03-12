## ADDED Requirements

### Requirement: Replace UTF-16 range with new text
The `TextRope` type SHALL provide a `mutating func replace(range utf16Range: NSRange, with string: String)` method that replaces the content in the specified UTF-16 code unit range with the given string. The range MUST be valid: `utf16Range.location >= 0`, `utf16Range.location + utf16Range.length <= utf16Count`. After replacement, the rope's `utf16Count` SHALL equal the previous `utf16Count` minus `utf16Range.length` plus the replacement string's UTF-16 length. The rope's `content` SHALL equal the original content with the specified range removed and the new string spliced in at that position.

#### Scenario: Replace within a single leaf
- **WHEN** a rope contains `"hello world"` and `replace(range: NSRange(location: 5, length: 6), with: " there")` is called
- **THEN** `content` is `"hello there"` and `utf16Count` is `11`

#### Scenario: Replace with shorter text
- **WHEN** a rope contains `"hello world"` and `replace(range: NSRange(location: 0, length: 11), with: "hi")` is called
- **THEN** `content` is `"hi"` and `utf16Count` is `2`

#### Scenario: Replace with longer text
- **WHEN** a rope contains `"hi"` and `replace(range: NSRange(location: 0, length: 2), with: "hello world")` is called
- **THEN** `content` is `"hello world"` and `utf16Count` is `11`

#### Scenario: Replace spanning multiple leaves
- **WHEN** a multi-leaf rope has content `"aaa...bbb...ccc"` (spanning 3+ leaves) and a replace range spans from the first leaf into the third leaf
- **THEN** `content` equals the expected result with the spanned region replaced and `utf16Count` is correct

#### Scenario: Replace with multi-byte characters
- **WHEN** a rope contains `"café"` (UTF-16 length 4) and `replace(range: NSRange(location: 3, length: 1), with: "🎉")` is called
- **THEN** `content` is `"caf🎉"` and `utf16Count` is `5` (emoji is 2 UTF-16 code units)

#### Scenario: Replace same-length text
- **WHEN** a rope contains `"abcdef"` and `replace(range: NSRange(location: 2, length: 2), with: "XX")` is called
- **THEN** `content` is `"abXXef"` and `utf16Count` is `6`

### Requirement: Empty replacement string degenerates to delete
When `replace(range:with:)` is called with an empty replacement string and a non-empty range, the operation SHALL behave identically to `delete(in:)` for that range. No insert operation SHALL occur.

#### Scenario: Replace with empty string deletes the range
- **WHEN** a rope contains `"hello world"` and `replace(range: NSRange(location: 5, length: 6), with: "")` is called
- **THEN** `content` is `"hello"` and `utf16Count` is `5`

#### Scenario: Replace entire content with empty string
- **WHEN** a rope contains `"hello"` and `replace(range: NSRange(location: 0, length: 5), with: "")` is called
- **THEN** `content` is `""`, `utf16Count` is `0`, and `isEmpty` is `true`

### Requirement: Empty range degenerates to insert
When `replace(range:with:)` is called with a zero-length range and a non-empty replacement string, the operation SHALL behave identically to `insert(_:at:)` at the range's location. No delete operation SHALL occur.

#### Scenario: Replace with empty range inserts at location
- **WHEN** a rope contains `"helloworld"` and `replace(range: NSRange(location: 5, length: 0), with: " ")` is called
- **THEN** `content` is `"hello world"` and `utf16Count` is `11`

#### Scenario: Replace with empty range at start
- **WHEN** a rope contains `"world"` and `replace(range: NSRange(location: 0, length: 0), with: "hello ")` is called
- **THEN** `content` is `"hello world"`

#### Scenario: Replace with empty range at end
- **WHEN** a rope contains `"hello"` and `replace(range: NSRange(location: 5, length: 0), with: " world")` is called
- **THEN** `content` is `"hello world"`

### Requirement: Both empty is a no-op
When `replace(range:with:)` is called with a zero-length range and an empty replacement string, the operation SHALL be a no-op. The rope's content and structure MUST remain unchanged.

#### Scenario: Empty range and empty string
- **WHEN** a rope contains `"hello"` and `replace(range: NSRange(location: 3, length: 0), with: "")` is called
- **THEN** `content` remains `"hello"` and the tree structure is unchanged

### Requirement: Summary correctness after replace
After any call to `replace(range:with:)`, every node in the tree MUST have a correct summary. The root summary MUST reflect the total UTF-8 byte count, UTF-16 code unit count, and newline count of the entire rope content.

#### Scenario: Summary after replacing text with newlines
- **WHEN** a rope contains `"line1\nline2\nline3"` and `replace(range: NSRange(location: 5, length: 6), with: "\nx\ny\nz")` is called
- **THEN** `root.summary.lines` equals the number of `\n` characters in the resulting content, and `root.summary.utf8` and `root.summary.utf16` match `Summary.of(rope.content)`

#### Scenario: Summary after replace with emoji
- **WHEN** a rope contains `"abc"` and `replace(range: NSRange(location: 1, length: 1), with: "🎉")` is called
- **THEN** `root.summary.utf8` is `6` (1 + 4 + 1), `root.summary.utf16` is `4` (1 + 2 + 1), and `root.summary.lines` is `0`

#### Scenario: Summary consistency after replace spanning leaves
- **WHEN** a multi-leaf rope undergoes a replace that spans multiple leaves
- **THEN** a full tree traversal confirms every inner node's summary equals the sum of its children's summaries, and the root summary matches `Summary.of(rope.content)`

### Requirement: COW independence on replace
When a `TextRope` value is copied and one copy is mutated via `replace`, the mutation SHALL NOT affect the other copy. Both `delete` and `insert` steps of the composed operation MUST respect COW path-copying discipline.

#### Scenario: Replace on shared rope preserves original
- **WHEN** `var a = TextRope("hello world")`, `var b = a`, then `b.replace(range: NSRange(location: 0, length: 5), with: "goodbye")`
- **THEN** `a.content` is `"hello world"` and `b.content` is `"goodbye world"`

#### Scenario: Single-owner replace avoids unnecessary copying
- **WHEN** a `TextRope` has a single owner (no copies exist) and `replace` is called
- **THEN** the mutation modifies nodes in place without allocating new node objects along the path
