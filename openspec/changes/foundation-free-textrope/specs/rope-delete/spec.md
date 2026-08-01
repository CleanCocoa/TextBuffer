## MODIFIED Requirements

### Requirement: Delete a UTF-16 range

The `TextRope` type SHALL provide a `mutating func delete(in utf16Range: Range<Int>)` method that removes the content within the specified half-open UTF-16 code unit range. The range MUST be valid: `utf16Range.lowerBound >= 0`, `utf16Range.upperBound <= utf16Count`. After deletion, the rope's `utf16Count` SHALL equal the previous `utf16Count` minus the deleted range's `count`. The rope's `content` SHALL equal the original content with the specified range removed.

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
- **WHEN** `delete(in: 3..<3)` is called on a rope containing `"hello"`
- **THEN** `content` remains `"hello"` and the tree structure is unchanged

#### Scenario: Delete with multi-byte characters
- **WHEN** a rope contains `"café🎉"` (UTF-16 length 6) and `delete(in: 4..<6)` is called
- **THEN** `content` is `"café"` and `utf16Count` is `4` (emoji was 2 UTF-16 code units)

#### Scenario: Delete spanning a surrogate pair boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16: `a`, high surrogate, low surrogate, `b` — length 4) and `delete(in: 1..<3)` is called
- **THEN** `content` is `"ab"` — the entire emoji is removed

#### Scenario: Out-of-bounds range traps
- **WHEN** `delete(in:)` is called with `lowerBound < 0` or `upperBound > utf16Count`
- **THEN** a precondition failure MUST occur

### Requirement: COW path-copying on delete

When a `TextRope` value is copied (via Swift's value semantics) and one copy is mutated via `delete`, the mutation SHALL NOT affect the other copy. The implementation MUST use copy-on-write path-copying: only nodes along the mutation path from root to the affected leaves are copied. Shared subtrees not on the mutation path MUST remain shared (reference-identical).

#### Scenario: Delete on shared rope preserves original
- **WHEN** `var a = TextRope("hello world")`, `var b = a`, then `b.delete(in: 5..<11)`
- **THEN** `a.content` is `"hello world"` and `b.content` is `"hello"`

#### Scenario: Path-copying shares unaffected subtrees
- **WHEN** a multi-leaf rope is copied and one copy is mutated via delete
- **THEN** nodes not on the root-to-affected-leaf mutation path remain reference-identical between the two copies

#### Scenario: Single-owner mutation avoids copying
- **WHEN** a `TextRope` has a single owner (no copies exist) and `delete` is called
- **THEN** the mutation modifies nodes in place without allocating new node objects along the path

### Requirement: Always-rooted invariant on delete-all

When the entire content of the rope is deleted, the result MUST be an empty leaf root — not nil, not an inner node with no children. The rope's `isEmpty` property SHALL return `true`. The rope's `utf16Count`, `utf8Count` SHALL be `0`. The rope's `content` SHALL be an empty string.

#### Scenario: Delete all content from a single-leaf rope
- **WHEN** a rope contains `"hello"` and `delete(in: 0..<5)` is called
- **THEN** `content` is `""`, `isEmpty` is `true`, `utf16Count` is `0`, and the root is a leaf node

#### Scenario: Delete all content from a multi-level rope
- **WHEN** a multi-level rope with many leaves has its entire content deleted via `delete(in: 0..<utf16Count)`
- **THEN** `content` is `""`, `isEmpty` is `true`, and the root is an empty leaf node (not an inner node, not nil)

#### Scenario: Rope is usable after delete-all
- **WHEN** all content is deleted from a rope and then new content is inserted
- **THEN** the rope functions correctly — `insert("new", at: 0)` results in `content` being `"new"`

### Requirement: Summary correctness after delete

After any call to `delete(in:)`, every node in the tree MUST have a correct summary. For leaf nodes, the summary MUST equal `Summary.of(chunk)`. For inner nodes, the summary MUST equal the sum of all children's summaries. The root summary MUST reflect the total UTF-8 byte count, UTF-16 code unit count, and newline count of the entire rope content.

#### Scenario: Summary after simple delete
- **WHEN** a rope contains `"hello\nworld"` and `delete(in: 5..<11)` is called
- **THEN** `root.summary.utf8` is `5`, `root.summary.utf16` is `5`, and `root.summary.lines` is `0`

#### Scenario: Summary after delete with multi-byte characters
- **WHEN** a rope contains `"🎉hello"` (utf8: 9, utf16: 7) and `delete(in: 0..<2)` is called (removes the emoji)
- **THEN** `root.summary.utf8` is `5`, `root.summary.utf16` is `5`, and `root.summary.lines` is `0`

#### Scenario: Summary consistency across tree after merge
- **WHEN** a deletion triggers leaf merges and inner node merges
- **THEN** a full tree traversal confirms that every inner node's summary equals the sum of its children's summaries, and the root summary matches a fresh `Summary.of(rope.content)`

#### Scenario: Summary after delete preserving newlines
- **WHEN** a rope contains `"line1\nline2\nline3"` and `delete(in: 5..<11)` is called (removes `"\nline2"`)
- **THEN** `root.summary.lines` is `1` (one remaining `\n` between "line1" and "\nline3" — content is `"line1\nline3"`)
