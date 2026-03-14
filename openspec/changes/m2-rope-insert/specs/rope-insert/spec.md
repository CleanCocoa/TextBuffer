## ADDED Requirements

### Requirement: Insert at UTF-16 offset
The `TextRope` type SHALL provide a `mutating func insert(_ string: String, at utf16Offset: Int)` method that inserts the given string at the specified UTF-16 code unit offset. The offset MUST be in the range `0...utf16Count`. After insertion, the rope's `utf16Count` SHALL equal the previous `utf16Count` plus the inserted string's UTF-16 length. The rope's `content` SHALL equal the original content with the string spliced at the corresponding position.

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
- **WHEN** `insert("", at: 0)` is called on a rope containing `"hello"`
- **THEN** `content` remains `"hello"` and the tree structure is unchanged

#### Scenario: Insert with multi-byte characters
- **WHEN** a rope contains `"café"` (UTF-16 length 4) and `insert("🎉", at: 4)` is called
- **THEN** `content` is `"café🎉"` and `utf16Count` is `6` (emoji is 2 UTF-16 code units)

#### Scenario: Insert between surrogate pair boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16: `a`, high surrogate, low surrogate, `b`) and `insert("x", at: 1)` is called
- **THEN** `content` is `"ax🎉b"` — the insertion goes before the emoji, not between surrogate halves

### Requirement: COW path-copying on insert
When a `TextRope` value is copied (via Swift's value semantics) and one copy is mutated via `insert`, the mutation SHALL NOT affect the other copy. The implementation MUST use copy-on-write path-copying: only nodes along the mutation path from root to the affected leaf are copied. Shared subtrees not on the mutation path MUST remain shared (reference-identical).

#### Scenario: Insert on shared rope preserves original
- **WHEN** `var a = TextRope("hello")`, `var b = a`, then `b.insert(" world", at: 5)`
- **THEN** `a.content` is `"hello"` and `b.content` is `"hello world"`

#### Scenario: Path-copying shares unaffected subtrees
- **WHEN** a multi-leaf rope is copied and one copy is mutated via insert
- **THEN** nodes not on the root-to-leaf mutation path remain reference-identical between the two copies

#### Scenario: Single-owner mutation avoids copying
- **WHEN** a `TextRope` has a single owner (no copies exist) and `insert` is called
- **THEN** the mutation modifies nodes in place without allocating new node objects along the path

### Requirement: Leaf splitting on overflow
When an insertion causes a leaf's chunk to exceed `Node.maxChunkUTF8` bytes, the leaf MUST be split into two leaves. The split point SHALL be at or near the midpoint of the chunk in UTF-8 bytes. The split point MUST fall on a valid UTF-8 character boundary (never in the middle of a multi-byte sequence). Both resulting chunks MUST have non-zero length.

#### Scenario: Small insert does not trigger split
- **WHEN** a leaf has 1000 UTF-8 bytes and 10 bytes are inserted
- **THEN** the leaf remains a single leaf with 1010 bytes (under `maxChunkUTF8` of 2048)

#### Scenario: Insert triggers leaf split
- **WHEN** an insertion causes a leaf's chunk to exceed `maxChunkUTF8` bytes
- **THEN** the leaf is split into two leaves, each containing a portion of the chunk, and the parent inner node gains an additional child

#### Scenario: Split respects UTF-8 character boundaries
- **WHEN** a leaf overflows and the naive midpoint falls inside a multi-byte UTF-8 sequence
- **THEN** the split point is adjusted to the nearest character boundary so both chunks contain valid UTF-8

#### Scenario: Large insertion causes multiple splits
- **WHEN** a string larger than `maxChunkUTF8` is inserted into a leaf
- **THEN** the result is multiple leaf nodes, each within the `maxChunkUTF8` limit, with correct content and summaries

### Requirement: Split invariant for CRLF
When splitting a leaf chunk, the split point MUST NOT fall between a `\r` (carriage return) and `\n` (line feed). If the byte immediately before the candidate split point is `\r` and the byte at the split point is `\n`, the split point SHALL be adjusted so that the `\r\n` pair remains in the same chunk.

#### Scenario: Split point between CR and LF is adjusted
- **WHEN** a leaf overflows and the midpoint split would place `\r` at the end of the left chunk and `\n` at the start of the right chunk
- **THEN** the split point is adjusted so that `\r\n` remains together in one chunk

#### Scenario: Isolated CR or LF at split boundary is allowed
- **WHEN** a leaf overflows and the midpoint split places a lone `\r` at the end of the left chunk (not followed by `\n`)
- **THEN** the split proceeds at that point without adjustment

#### Scenario: Line count correctness after CRLF-aware split
- **WHEN** a chunk containing `"aaa\r\nbbb\r\nccc"` is split
- **THEN** the sum of `lines` in the two resulting leaf summaries equals the line count of the original chunk

### Requirement: Split propagation through inner nodes
When a leaf split adds a child to an inner node that already has `Node.maxChildren` children, the inner node MUST itself split into two inner nodes. This split SHALL propagate upward as needed. If the root node splits, the `TextRope` MUST create a new root with the two halves as children, increasing the tree height by one.

#### Scenario: Leaf split within inner node capacity
- **WHEN** a leaf splits and the parent inner node has fewer than `maxChildren` children
- **THEN** the new leaf is inserted into the parent's children array and the parent's summary is updated

#### Scenario: Inner node overflow triggers split
- **WHEN** a leaf split causes a parent inner node to exceed `maxChildren` children
- **THEN** the inner node splits into two inner nodes, each with a valid number of children, and the split propagates to the grandparent

#### Scenario: Root split increases tree height
- **WHEN** the root node itself overflows due to a propagating split
- **THEN** a new root is created with the two halves as children, the tree height increases by one, and all summaries are correct

#### Scenario: Cascading splits maintain correct summaries
- **WHEN** a single insert triggers splits at multiple levels of the tree
- **THEN** every node's summary (utf8, utf16, lines) equals the sum of its children's summaries (for inner nodes) or the metrics of its chunk (for leaves)

### Requirement: Summary correctness after insert
After any call to `insert(_:at:)`, every node in the tree MUST have a correct summary. For leaf nodes, the summary MUST equal `Summary.of(chunk)`. For inner nodes, the summary MUST equal the sum of all children's summaries. The root summary MUST reflect the total UTF-8 byte count, UTF-16 code unit count, and newline count of the entire rope content.

#### Scenario: Summary after simple insert
- **WHEN** `insert("hello\nworld", at: 0)` is called on an empty rope
- **THEN** `root.summary.utf8` is `11`, `root.summary.utf16` is `11`, and `root.summary.lines` is `1`

#### Scenario: Summary after insert with emoji
- **WHEN** `insert("🎉", at: 0)` is called on an empty rope
- **THEN** `root.summary.utf8` is `4`, `root.summary.utf16` is `2`, and `root.summary.lines` is `0`

#### Scenario: Summary consistency across tree after multi-level split
- **WHEN** repeated insertions cause the tree to grow to multiple levels with splits
- **THEN** a full tree traversal confirms that every inner node's summary equals the sum of its children's summaries, and the root summary matches a fresh `Summary.of(rope.content)`
