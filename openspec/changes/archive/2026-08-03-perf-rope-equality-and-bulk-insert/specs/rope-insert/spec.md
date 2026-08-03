## MODIFIED Requirements

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
