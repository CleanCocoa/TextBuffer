# rope-insert Specification

## Purpose
Guarantees correct insertion at any UTF-16 offset of a `TextRope`: content is spliced exactly where requested (never between surrogate halves), an overflowing leaf is re-chunked in a single linear pass through the same grapheme-first split helper construction and redistribution use, splits propagate upward with uniform leaf depth and exact summaries at every node, a `\r\n` seam left at a leaf boundary is repaired without violating the chunk-size bounds, and copy-on-write path-copying keeps shared copies independent while a single-owner insert mutates in place.
## Requirements
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

> Rebased on the `fix-rope-split-point` delta for this requirement, which lands first and establishes the shared grapheme-first split helper. This version generalizes its two-leaf split to a single-pass n-leaf re-chunk; split-point selection itself is unchanged from that change and ADR-012.

When an insertion causes a leaf's chunk to exceed `Node.maxChunkUTF8` bytes, the leaf MUST be replaced by two or more leaves covering the same text in the same order. Per ADR-012, every split point MUST fall on a `Character` (grapheme cluster) boundary — never inside a multi-byte UTF-8 sequence and never between a `\r` and its following `\n`, since CRLF is a single `Character`. Every resulting chunk MUST have non-zero length.

The overflowing chunk MUST be re-chunked in a **single pass** over its bytes, regardless of how much text was inserted. An implementation MUST NOT repeatedly split off one chunk at a time in a way that re-copies the remaining tail on each round: inserting a string of `n` bytes SHALL cost O(n) byte copying at the affected leaf, not O(n² / maxChunkUTF8). This SHALL hold whether the affected leaf is the root or a leaf below one or more inner nodes — both cases SHALL use the same chunking procedure, and that procedure SHALL select split points through the same grapheme-first helper used by construction and redistribution, so all three paths obey one rule.

Chunk sizes obey ADR-012's grapheme-first bounds: every chunk produced by re-chunking an overflowing leaf MUST be within `[Node.minChunkUTF8, Node.maxChunkUTF8]` UTF-8 bytes **whenever a conforming `Character` boundary exists**. Under boundary starvation — no `Character` boundary yields a conforming split — the nearest-boundary minimal-deviation split SHALL be taken, and a single grapheme cluster larger than `maxChunkUTF8` SHALL occupy one whole-cluster leaf of whatever size it needs. If the whole spliced chunk still fits within `maxChunkUTF8`, no split occurs and the single chunk keeps whatever size it had.

The exact split offsets are NOT specified. Two implementations satisfying the bounds above may place chunk boundaries differently; leaf shape is internal and no requirement SHALL be read as pinning it. Rope content, per-node summaries, leaf depth uniformity, and the `\r\n` invariant are the observable contract.

#### Scenario: Small insert does not trigger split
- **WHEN** a leaf has 1000 UTF-8 bytes and 10 bytes are inserted
- **THEN** the leaf remains a single leaf with 1010 bytes (under `maxChunkUTF8` of 2048)

#### Scenario: Insert triggers leaf split
- **WHEN** an insertion causes a leaf's chunk to exceed `maxChunkUTF8` bytes
- **THEN** the leaf is replaced by two or more leaves, together containing exactly the original chunk's text, and the parent inner node gains the additional children

#### Scenario: Split respects UTF-8 character boundaries
- **WHEN** a leaf overflows and the naive midpoint falls inside a multi-byte UTF-8 sequence
- **THEN** the split point is adjusted to the nearest `Character` boundary so both chunks contain valid UTF-8 (subsumed by the grapheme-cluster rule below)

#### Scenario: Split respects grapheme cluster boundaries
- **WHEN** a leaf overflows and a candidate split point falls inside a multi-byte UTF-8 sequence or inside a grapheme cluster
- **THEN** the split point is adjusted to a `Character` boundary so no chunk seam falls inside a cluster and every chunk contains valid UTF-8

#### Scenario: Oversized grapheme cluster is not split
- **WHEN** an insertion produces a chunk that consists of, or is dominated by, a single grapheme cluster larger than `maxChunkUTF8` bytes, so no `Character` boundary yields a conforming split
- **THEN** the cluster SHALL end up whole inside one leaf — the implementation SHALL NOT place a split point inside the cluster

#### Scenario: Split searches forward when the backward boundary is illegal
- **WHEN** a 2049-byte chunk overflows and a 4-byte scalar occupies bytes `[1022, 1026)`, so the boundary below the midpoint would leave a 1022-byte chunk
- **THEN** the split SHALL be taken at offset 1026, leaving chunks of 1026 and 1023 bytes — the minimal-deviation choice per ADR-012; the backward-only outcome of 1022 and 1027 SHALL NOT be produced

#### Scenario: Large insertion causes multiple splits
- **WHEN** a string larger than `maxChunkUTF8` is inserted into a leaf
- **THEN** the result is multiple leaf nodes, each within the `maxChunkUTF8` limit, with correct content and summaries

#### Scenario: Bulk insert into a non-root leaf re-chunks in one pass
- **WHEN** a string many times larger than `maxChunkUTF8` is inserted into a leaf that sits below one or more inner nodes
- **THEN** the spliced chunk is chunked in a single pass, the mutated leaf keeps the first chunk, and the remaining chunks are handed to the parent as new siblings in one batch — the tail is not re-copied once per produced chunk

#### Scenario: Bulk insert cost grows linearly with inserted length
- **WHEN** the inserted string's length is quadrupled and inserted at the same position in an equivalent rope
- **THEN** the work performed at the affected leaf SHALL grow proportionally to the inserted length, not to its square

#### Scenario: Re-chunked leaves respect the grapheme-first chunk bounds
- **WHEN** an overflowing leaf is re-chunked
- **THEN** every resulting chunk is at least `minChunkUTF8` and at most `maxChunkUTF8` UTF-8 bytes wherever a conforming `Character` boundary exists, and any out-of-bounds chunk SHALL be attributable to provable boundary starvation per ADR-012 (verified by tree-invariant validation, not tolerated by a fuzzy allowance)

#### Scenario: Root-leaf and non-root-leaf overflow behave identically
- **WHEN** the same text is inserted at the same relative position into a single-leaf rope and into a leaf of a multi-level rope
- **THEN** both paths use the same chunking procedure and both satisfy the same grapheme-first chunk bounds, summary consistency, and `\r\n` invariant

#### Scenario: CRLF pairs survive bulk re-chunking
- **WHEN** an inserted string containing `\r\n` pairs overflows a leaf and is re-chunked into many leaves
- **THEN** no `\r\n` pair is split across adjacent leaves — CRLF is a single `Character`, so grapheme-first splitting forbids it structurally — and the sum of `lines` across the resulting leaf summaries equals the line count of the combined text

#### Scenario: Wide sibling batch propagates through inner node splitting
- **WHEN** re-chunking produces far more siblings than `Node.maxChildren` for a single parent
- **THEN** the parent splits n-way, the split propagates upward as needed, leaf depth remains uniform, and the root summary equals the summary of the full rope content

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

### Requirement: CRLF seam repair preserves chunk size bounds

> Generalized by `fix-grapheme-seam-repair` (DEF-016): the repair covers **every** grapheme seam, with the `\r`/`\n` adjacency as the named special case — `\r\n` is a single Swift `Character`, so the CRLF machinery was always an instance of this rule.

When an insertion leaves two adjacent leaves whose edge `Character`s join into a single grapheme cluster — the concatenation of the left leaf's last `Character` and the right leaf's first `Character` forms fewer than two `Character`s under Swift stdlib grapheme segmentation — the implementation MUST repair the seam so the cluster ends up in a single chunk. This includes, as one instance, a `\r` at the end of one leaf with a `\n` at the start of the following leaf, and equally a base character whose combining mark, ZWJ continuation, or variation selector begins the following leaf. Seam detection uses Swift `Character` segmentation only (the TextRope target is Foundation-free per ADR-013); NSString composed-sequence parity is out of scope for this requirement.

The seam check MUST run **unconditionally** on the mutation-touched adjacency of every insert descent — it MUST NOT be gated on either leaf being undersized or oversized, since an adjacency-formed cluster (for example a lone combining mark spliced at leaf-local offset 0) arises with both leaves inside their byte bounds.

The repair SHALL operate on the two leaves' concatenated content and redistribute it under the window-clamped split rules:

- combined size at most `maxChunkUTF8` → the two leaves become **one** leaf, and the emptied leaf is removed from its parent;
- window holds a `Character` boundary → two leaves, both within `[minChunkUTF8, maxChunkUTF8]`;
- window holds no boundary and the combined size is at least `3 * minChunkUTF8` → **three** leaves by balanced redistribution, each within `[minChunkUTF8, maxChunkUTF8]`. The additional leaf SHALL be returned to the insertion path as an overflow sibling and spliced between the two, and any resulting inner-node overflow SHALL propagate exactly as a leaf split does;
- otherwise, boundary starvation applies and the repair MAY legally produce a minimal-shortfall undersized leaf, or a whole-cluster oversized leaf, per the grapheme-first chunk-size bounds (ADR-012). The seam invariant is absolute; the byte bounds yield only under proven starvation.

Because redistribution selects split points at `Character` boundaries only, the repaired seam cannot itself fall inside a cluster.

Summaries along both affected root-to-leaf paths MUST be recomputed after the repair.

#### Scenario: Seam repair on two full leaves produces three legal leaves
- **WHEN** a rope holds leaves of 2048 and 2047 bytes, the first ending in `\r`, and `\n` is inserted at the start of the second so the combined content is 4096 bytes with the seam exactly at the only offset in the window
- **THEN** the affected leaves SHALL be replaced by three leaves, each between `minChunkUTF8` and `maxChunkUTF8` bytes, with `\r\n` intact in one chunk and the rope's `content` unchanged apart from the inserted `\n`
- **AND** no leaf SHALL exceed `maxChunkUTF8`

#### Scenario: Combining mark inserted at a leaf boundary is repaired without a size trigger
- **WHEN** a rope holds `String(repeating: "a", count: 4096)` and `insert("\u{301}", at: 2048)` splices a lone combining acute at leaf-local offset 0 of the right leaf, so that after overflow re-chunking no edge chunk is undersized
- **THEN** the seam between the untouched left leaf and the spliced run SHALL still be checked and repaired: no grapheme cluster SHALL span any leaf seam, and `content`, `utf16Count`, and `utf8Count` SHALL match the oracle

#### Scenario: Seam check is not gated on chunk sizes
- **WHEN** an insertion changes the first `Character` of a leaf whose byte size, and whose left neighbor's byte size, both remain within `[minChunkUTF8, maxChunkUTF8]`
- **THEN** the grapheme-seam check SHALL run on that adjacency regardless, and a joining pair SHALL be repaired

#### Scenario: Repair output may be a legal starved shape
- **WHEN** a seam repair's combined content admits no conforming split — for example the joined cluster is itself larger than `maxChunkUTF8`, or the window holds no `Character` boundary in the residual band
- **THEN** the repair SHALL keep the cluster whole (whole-cluster oversized leaf) or take the minimal-shortfall split, and tree-invariant validation SHALL accept the result under the ADR-012 starvation predicates while the seam invariant holds

#### Scenario: Seam repair on a small combination does not split
- **WHEN** the two leaves at a `\r\n` seam have a combined size of at most `maxChunkUTF8`
- **THEN** the result SHALL be a single leaf holding the combined content, and the parent's child count SHALL decrease by one

#### Scenario: Seam repair overflow propagates like a split
- **WHEN** a seam repair adds a leaf to an inner node that already holds `maxChildren` children
- **THEN** the inner node SHALL split and the split SHALL propagate upward, increasing tree height if the root overflows

#### Scenario: Summaries are correct after seam repair
- **WHEN** a seam repair changes the chunk contents of two leaves or adds a third
- **THEN** every node on both affected paths SHALL have a summary equal to `Summary.of(chunk)` for leaves and the sum of children's summaries for inner nodes

