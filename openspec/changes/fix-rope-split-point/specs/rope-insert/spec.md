## ADDED Requirements

### Requirement: CRLF seam repair preserves chunk size bounds

When an insertion leaves a `\r` at the end of one leaf and a `\n` at the start of the following leaf, the implementation MUST repair the seam so the pair ends up in a single chunk. The repair MUST NOT produce a chunk violating the grapheme-first chunk-size bounds.

The repair SHALL operate on the two leaves' concatenated content and redistribute it under the window-clamped split rules:

- combined size at most `maxChunkUTF8` → the two leaves become **one** leaf, and the emptied leaf is removed from its parent;
- window holds a `Character` boundary → two leaves, both within `[minChunkUTF8, maxChunkUTF8]`;
- window holds no boundary and the combined size is at least `3 * minChunkUTF8` → **three** leaves by balanced redistribution, each within `[minChunkUTF8, maxChunkUTF8]`. The additional leaf SHALL be returned to the insertion path as an overflow sibling and spliced between the two, and any resulting inner-node overflow SHALL propagate exactly as a leaf split does.

Summaries along both affected root-to-leaf paths MUST be recomputed after the repair.

#### Scenario: Seam repair on two full leaves produces three legal leaves
- **WHEN** a rope holds leaves of 2048 and 2047 bytes, the first ending in `\r`, and `\n` is inserted at the start of the second so the combined content is 4096 bytes with the seam exactly at the only offset in the window
- **THEN** the affected leaves SHALL be replaced by three leaves, each between `minChunkUTF8` and `maxChunkUTF8` bytes, with `\r\n` intact in one chunk and the rope's `content` unchanged apart from the inserted `\n`
- **AND** no leaf SHALL exceed `maxChunkUTF8`

#### Scenario: Seam repair on a small combination does not split
- **WHEN** the two leaves at a `\r\n` seam have a combined size of at most `maxChunkUTF8`
- **THEN** the result SHALL be a single leaf holding the combined content, and the parent's child count SHALL decrease by one

#### Scenario: Seam repair overflow propagates like a split
- **WHEN** a seam repair adds a leaf to an inner node that already holds `maxChildren` children
- **THEN** the inner node SHALL split and the split SHALL propagate upward, increasing tree height if the root overflows

#### Scenario: Summaries are correct after seam repair
- **WHEN** a seam repair changes the chunk contents of two leaves or adds a third
- **THEN** every node on both affected paths SHALL have a summary equal to `Summary.of(chunk)` for leaves and the sum of children's summaries for inner nodes

## MODIFIED Requirements

### Requirement: Leaf splitting on overflow
When an insertion causes a leaf's chunk to exceed `Node.maxChunkUTF8` bytes, the leaf MUST be split into two leaves. The split point SHALL be at or near the midpoint of the chunk in UTF-8 bytes when the chunk is smaller than `maxChunkUTF8 + minChunkUTF8`, and at the largest conforming offset not exceeding `maxChunkUTF8` otherwise, so the remainder can be re-split by the caller. The split point MUST fall on a `Character` (grapheme cluster) boundary — never inside a cluster, not even at a Unicode scalar boundary — and MUST be found by searching **both** directions from the target offset, clamped to the legal window `[max(minChunkUTF8, count - maxChunkUTF8), min(maxChunkUTF8, count - minChunkUTF8)]`. The search MUST NOT walk below the window's lower end. Both resulting chunks MUST have non-zero length, and neither SHALL fall below `minChunkUTF8` when a `Character` boundary in the window would have avoided it. When no `Character` boundary yields a conforming split, the minimal-deviation split of the grapheme-first bounds requirement applies; a single grapheme cluster larger than `maxChunkUTF8` is never split and occupies one whole-cluster leaf.

#### Scenario: Small insert does not trigger split
- **WHEN** a leaf has 1000 UTF-8 bytes and 10 bytes are inserted
- **THEN** the leaf remains a single leaf with 1010 bytes (under `maxChunkUTF8` of 2048)

#### Scenario: Insert triggers leaf split
- **WHEN** an insertion causes a leaf's chunk to exceed `maxChunkUTF8` bytes
- **THEN** the leaf is split into two leaves, each containing a portion of the chunk, and the parent inner node gains an additional child

#### Scenario: Split respects grapheme cluster boundaries
- **WHEN** a leaf overflows and the naive midpoint falls inside a multi-byte UTF-8 sequence or a multi-scalar grapheme cluster
- **THEN** the split point is adjusted to the nearest `Character` boundary so no cluster spans the chunk seam

#### Scenario: Split searches forward when the backward boundary is illegal
- **WHEN** a 2049-byte chunk overflows and a 4-byte scalar occupies bytes `[1022, 1026)`, so the boundary below the midpoint would leave a 1022-byte chunk
- **THEN** the split SHALL be taken at offset 1026, leaving chunks of 1026 and 1023 bytes — the backward-only outcome of 1022 and 1027 SHALL NOT be produced

#### Scenario: Oversized grapheme cluster is not split
- **WHEN** an insertion produces a chunk that consists of, or is dominated by, a single grapheme cluster larger than `maxChunkUTF8` bytes, so no `Character` boundary yields a conforming split
- **THEN** the cluster SHALL end up whole inside one leaf — the implementation SHALL NOT place a split point inside the cluster

#### Scenario: Large insertion causes multiple splits
- **WHEN** a string larger than `maxChunkUTF8` is inserted into a leaf
- **THEN** the result is multiple leaf nodes, each within the `maxChunkUTF8` limit, with correct content and summaries
