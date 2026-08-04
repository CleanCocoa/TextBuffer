## MODIFIED Requirements

### Requirement: Insert at UTF-16 offset
The `TextRope` type SHALL provide a `mutating func insert(_ string: String, at utf16Offset: Int)` method that inserts the given string at the specified UTF-16 code unit offset. The offset MUST be in the range `0...utf16Count`. After insertion, the rope's `utf16Count` SHALL equal the previous `utf16Count` plus the inserted string's UTF-16 length. The rope's `content` SHALL equal the original content with the string spliced at the corresponding position.

Offset validation MUST precede the empty-string early return: an offset outside `0...utf16Count` MUST cause a precondition failure even when the string is empty. Inserting an empty string at an in-bounds offset SHALL be a no-op.

#### Scenario: Insert into empty rope
- **WHEN** `insert("hello", at: 0)` is called on an empty rope
- **THEN** `content` is `"hello"` and `utf16Count` is `5`

#### Scenario: Insert at the beginning
- **WHEN** a rope contains `"world"` and `insert("hello ", at: 0)` is called
- **THEN** `content` is `"hello world"`

#### Scenario: Insert at the end
- **WHEN** a rope contains `"hello"` and `insert(" world", at: 5)` is called
- **THEN** `content` is `"hello world"`

#### Scenario: Insert in the middle
- **WHEN** a rope contains `"hllo"` and `insert("e", at: 1)` is called
- **THEN** `content` is `"hello"`

#### Scenario: Insert empty string is a no-op
- **WHEN** `insert("", at: k)` is called with an in-bounds `k` (`0 <= k <= utf16Count`) — e.g. `insert("", at: 0)` on a rope containing `"hello"`
- **THEN** `content` remains `"hello"` and the tree structure is unchanged

#### Scenario: Insert with multi-byte characters
- **WHEN** a rope contains `"café"` (UTF-16 length 4) and `insert("🎉", at: 4)` is called
- **THEN** `content` is `"café🎉"` and `utf16Count` is `6` (emoji is 2 UTF-16 code units)

#### Scenario: Insert between surrogate pair boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16: `a`, high surrogate, low surrogate, `b`) and `insert("x", at: 1)` is called
- **THEN** `content` is `"ax🎉b"` — the insertion goes before the emoji, not between surrogate halves

#### Scenario: Out-of-bounds offset traps
- **WHEN** `insert(_:at:)` is called with an offset outside `0...utf16Count` — negative or past the end — whether the string is non-empty or empty, e.g. `insert("x", at: 500)` or `insert("", at: 500)` on a rope containing `"hello"`
- **THEN** a precondition failure MUST occur
- **AND** the empty-string call SHALL NOT silently succeed as a no-op
