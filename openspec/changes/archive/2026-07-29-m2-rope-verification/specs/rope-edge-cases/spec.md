## ADDED Requirements

### Requirement: CRLF invariant at chunk boundaries
The test suite MUST verify that the `\r\n` split invariant holds under mutation pressure. After any sequence of insert, delete, or replace operations on a rope containing `\r\n` pairs, no chunk boundary SHALL fall between a `\r` and its following `\n`. The line count in the root summary MUST equal the number of `\n` characters in the full content.

#### Scenario: Construction preserves CRLF pairs
- **WHEN** a `TextRope` is constructed from a string containing `\r\n` pairs sized to land `\r` at a chunk boundary
- **THEN** no leaf chunk ends with `\r` while the next chunk starts with `\n`

#### Scenario: Insert near CRLF at chunk boundary
- **WHEN** a `\r\n` pair sits at a chunk boundary and text is inserted immediately before the `\r`, at the `\r`, between `\r` and `\n`, or after the `\n`
- **THEN** after each insertion the `\r\n` invariant holds: no chunk boundary splits the pair, and line counts are correct

#### Scenario: Delete that removes half of CRLF pair
- **WHEN** a delete range covers only the `\r` of a `\r\n` pair, leaving a lone `\n`
- **THEN** the line count updates correctly (the `\n` still counts as a newline) and no invariant is violated

#### Scenario: Replace across CRLF pair
- **WHEN** a replace operation spans a `\r\n` pair (replacing it with other text)
- **THEN** `content` matches the expected result and the `\r\n` invariant holds for all remaining pairs

#### Scenario: Line count consistency after CRLF mutations
- **WHEN** multiple operations insert and delete `\r\n` pairs at various positions
- **THEN** the root summary's `lines` count always equals the number of `\n` bytes in `rope.content`

### Requirement: Surrogate pairs at range edges
The test suite MUST verify correct behavior when delete or replace operations have range boundaries that fall at a surrogate pair boundary in UTF-16. Since TextRope uses UTF-16 offsets at the public API, ranges that start or end between the high and low surrogate of an emoji character MUST be handled without corrupting content.

#### Scenario: Delete starting at surrogate boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16 offsets: a=0, high=1, low=2, b=3) and `delete(in: NSRange(location: 1, length: 2))` removes the full emoji
- **THEN** `content` is `"ab"` and summaries are correct

#### Scenario: Delete ending at surrogate boundary
- **WHEN** a rope contains `"a🎉b"` and `delete(in: NSRange(location: 0, length: 1))` removes just `"a"`
- **THEN** `content` is `"🎉b"` and the emoji is intact

#### Scenario: Replace spanning surrogate pair
- **WHEN** a rope contains `"a🎉b"` and `replace(range: NSRange(location: 1, length: 2), with: "XX")` replaces the emoji
- **THEN** `content` is `"aXXb"` and summaries are correct

#### Scenario: Delete range covering multiple emoji
- **WHEN** a rope contains `"🎉🚀💡"` (each emoji is 2 UTF-16 code units) and `delete(in: NSRange(location: 2, length: 2))` removes the middle emoji
- **THEN** `content` is `"🎉💡"` and `utf16Count` is `4`

#### Scenario: Large rope with emoji at chunk boundaries
- **WHEN** a multi-chunk rope is constructed such that an emoji's surrogate pair spans near a chunk boundary, and a delete/replace targets that region
- **THEN** `content` equals the expected result and no surrogate pair is corrupted

### Requirement: Repeated single-character operations
The test suite MUST verify rope correctness under repeated single-character insert and delete operations that force many leaf splits and merges. This exercises the rebalancing logic path that bulk operations may not trigger.

#### Scenario: 1000 single-char inserts at position 0
- **WHEN** 1000 single ASCII characters are inserted one at a time at position 0
- **THEN** `content` equals the expected reversed string, `utf16Count` is 1000, and tree structure is valid

#### Scenario: 1000 single-char inserts at end
- **WHEN** 1000 single ASCII characters are appended one at a time
- **THEN** `content` equals the concatenated string, and tree structure is valid (balanced, within B-tree constraints)

#### Scenario: Build up then tear down
- **WHEN** 1000 characters are inserted one at a time, then deleted one at a time from the end
- **THEN** after all deletions, `content` is `""`, `isEmpty` is `true`, and the rope is in a valid empty state

#### Scenario: Alternating insert and delete
- **WHEN** 2000 operations alternate between inserting a random character and deleting a random single-character range (when non-empty)
- **THEN** after all operations, `content` equals the oracle string and tree structure is valid

#### Scenario: Single-char inserts with multi-byte characters
- **WHEN** 500 emoji characters (4-byte UTF-8 each) are inserted one at a time at random positions
- **THEN** `content` equals the oracle string, `utf16Count` is `1000` (500 × 2 surrogate pairs), and tree structure is valid

### Requirement: Rebalancing produces valid B-tree structure
After any sequence of operations, the rope's tree structure MUST satisfy B-tree invariants: all leaves at the same depth, inner nodes have between `minChildren` and `maxChildren` children (root may have fewer), and leaf chunks are within `minChunkUTF8` and `maxChunkUTF8` bounds (small ropes and the last chunk may be smaller). The test suite MUST verify these invariants after edge-case and stress test sequences.

#### Scenario: Tree depth is uniform after stress
- **WHEN** 10,000 random operations have been applied
- **THEN** all leaves in the rope are at the same depth from the root

#### Scenario: Inner node child counts are within bounds
- **WHEN** 10,000 random operations have been applied
- **THEN** every non-root inner node has between `minChildren` and `maxChildren` children

#### Scenario: Leaf chunk sizes are within bounds
- **WHEN** a rope contains multiple chunks after sustained operations
- **THEN** every leaf chunk (except possibly the last) has a UTF-8 byte count between `minChunkUTF8` and `maxChunkUTF8`

#### Scenario: Single-leaf rope after deletion to small size
- **WHEN** a multi-leaf rope has most of its content deleted, leaving fewer than `minChunkUTF8` bytes
- **THEN** the rope collapses to a single leaf with valid summary, and `content` matches the expected remainder
