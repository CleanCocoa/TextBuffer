## MODIFIED Requirements

### Requirement: Delete a UTF-16 range

The `TextRope` type SHALL provide a `mutating func delete(in utf16Range: Range<Int>)` method that removes the content within the specified half-open UTF-16 code unit range. The range MUST be valid: `utf16Range.lowerBound >= 0`, `utf16Range.upperBound <= utf16Count`. After deletion, the rope's `utf16Count` SHALL equal the previous `utf16Count` minus the deleted range's `count`. The rope's `content` SHALL equal the original content with the specified range removed.

Bounds validation MUST precede the empty-range early return: an empty range at an out-of-bounds location MUST cause a precondition failure even though nothing would be deleted. An empty range at an in-bounds location (`0 <= k <= utf16Count` for `k..<k`) SHALL be a no-op.

#### Scenario: Delete from a single-leaf rope
- **WHEN** a rope contains `"hello world"` and `delete(in: 5..<11)` is called
- **THEN** `content` is `"hello"` and `utf16Count` is `5`

#### Scenario: Delete at the beginning
- **WHEN** a rope contains `"hello world"` and `delete(in: 0..<6)` is called
- **THEN** `content` is `"world"`

#### Scenario: Delete at the end
- **WHEN** a rope contains `"hello world"` and `delete(in: 5..<11)` is called
- **THEN** `content` is `"hello"`

#### Scenario: Delete in the middle
- **WHEN** a rope contains `"hello world"` and `delete(in: 2..<8)` is called
- **THEN** `content` is `"herld"`

#### Scenario: Delete empty range is a no-op
- **WHEN** `delete(in: k..<k)` is called with an in-bounds `k` (`0 <= k <= utf16Count`) — e.g. `delete(in: 3..<3)` on a rope containing `"hello"`
- **THEN** `content` remains `"hello"` and the tree structure is unchanged

#### Scenario: Delete with multi-byte characters
- **WHEN** a rope contains `"café🎉"` (UTF-16 length 6) and `delete(in: 4..<6)` is called
- **THEN** `content` is `"café"` and `utf16Count` is `4` (emoji was 2 UTF-16 code units)

#### Scenario: Delete spanning a surrogate pair boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16: `a`, high surrogate, low surrogate, `b` — length 4) and `delete(in: 1..<3)` is called
- **THEN** `content` is `"ab"` — the entire emoji is removed

#### Scenario: Out-of-bounds range traps
- **WHEN** `delete(in:)` is called with `lowerBound < 0` or `upperBound > utf16Count`
- **THEN** a precondition failure MUST occur, whether the range is empty or not

#### Scenario: Empty out-of-bounds range traps
- **WHEN** `delete(in: k..<k)` is called with `k > utf16Count` or `k < 0` — e.g. `delete(in: 500..<500)` on a rope containing `"hello"`
- **THEN** a precondition failure MUST occur
- **AND** the call SHALL NOT silently succeed as a no-op
