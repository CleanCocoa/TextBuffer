## ADDED Requirements

### Requirement: Chunk size bounds are grapheme-first

Chunk-size bounds follow ADR-012's grapheme-first regime. Split points anywhere in the implementation — construction, leaf splitting on insert overflow, and redistribution during merges — MUST fall on `Character` (grapheme cluster) boundaries only. A split point MUST NOT fall inside a grapheme cluster, not even at a Unicode scalar boundary. Consequently the `\r\n` never-split rule is absolute rather than a special case: `\r\n` is a single `Character`.

The byte bounds `[minChunkUTF8, maxChunkUTF8]` MUST hold for every leaf whenever a conforming `Character` boundary exists. They MAY be violated only under **boundary starvation** — when no `Character` boundary yields a conforming split — and then only minimally:

- A leaf's chunk MAY exceed `maxChunkUTF8` only when the chunk is a **single grapheme cluster** larger than `maxChunkUTF8`. The cluster occupies one whole-cluster leaf of whatever size it needs. There is no fixed byte cap on the excess and no scalar-boundary fallback.
- A leaf's chunk MAY fall below `minChunkUTF8` only when, for **each** adjacent sibling leaf `S`, both of the following hold:
  - `leaf.chunk.utf8.count + S.chunk.utf8.count > maxChunkUTF8` — merging outright is impossible, and
  - the combined slice has no `Character` boundary at any UTF-8 offset in `[max(minChunkUTF8, count - maxChunkUTF8), min(maxChunkUTF8, count - minChunkUTF8)]` — redistribution to two conforming chunks is impossible.

A rope whose entire content is smaller than `minChunkUTF8` is exempt: a single-leaf root has no size floor.

Starvation is provable per leaf from the tree alone, so tree-invariant validation MUST judge every out-of-bounds leaf against these exact predicates — no fuzzy tolerance constants. A leaf that violates the bounds without satisfying its starvation predicate is a defect and MUST be reported.

#### Scenario: Split points never fall inside a grapheme cluster
- **WHEN** any leaf chunk is produced by construction, by a split on insert overflow, or by redistribution during a merge
- **THEN** every chunk SHALL begin and end on a `Character` boundary of the document — no grapheme cluster SHALL span a chunk seam

#### Scenario: Oversized leaf is only permitted as a whole cluster
- **WHEN** a leaf's chunk exceeds `maxChunkUTF8` bytes
- **THEN** the chunk SHALL consist of exactly one grapheme cluster; an oversized chunk containing more than one `Character` is a violation

#### Scenario: Grapheme cluster larger than the maximum occupies one whole leaf
- **WHEN** the input contains a single grapheme cluster larger than `maxChunkUTF8` bytes (e.g. a long ZWJ chain or combining-mark run)
- **THEN** the entire cluster SHALL be stored in one leaf, unsplit, and validation SHALL accept that leaf

#### Scenario: Undersized leaf is only permitted when provably starved
- **WHEN** a leaf's chunk is below `minChunkUTF8` in a rope whose root is an inner node
- **THEN** for every adjacent sibling leaf, the combined size SHALL exceed `maxChunkUTF8` **and** the combined slice SHALL have no `Character` boundary inside its legal redistribution window

#### Scenario: Two leaves that could merge are never left undersized
- **WHEN** a leaf is below `minChunkUTF8` and an adjacent sibling's chunk brings the combined size to at most `maxChunkUTF8`
- **THEN** the two SHALL have been merged into one leaf — leaving both is a violation

#### Scenario: A 2049-byte combination straddled by a 4-byte scalar
- **WHEN** two leaves are redistributed whose combined slice is 2049 UTF-8 bytes with a 4-byte scalar occupying bytes `[1023, 1027)`, so the window `[1024, 1025]` holds no `Character` boundary
- **THEN** the result SHALL be two leaves of 1023 and 1026 bytes — the minimal-deviation split — and the 1023-byte leaf SHALL be accepted by invariant validation under the starvation predicate above

#### Scenario: Single leaf below the floor is legal
- **WHEN** a rope's entire content is shorter than `minChunkUTF8`
- **THEN** the root SHALL be a single leaf holding all of it, and its size SHALL NOT be reported as a violation

### Requirement: Split point selection is clamped to the legal window

When a slice of `count` UTF-8 bytes is split into two chunks, the split offset MUST fall within `[low, high]` where `low = max(minChunkUTF8, count - maxChunkUTF8)` and `high = min(maxChunkUTF8, count - minChunkUTF8)`, whenever that window is non-empty and contains a `Character` boundary. The search MUST proceed in **both** directions from the midpoint `(count + 1) / 2` and MUST NOT walk past either end of the window; ties SHALL resolve to the lower offset.

When the window contains no `Character` boundary the implementation MUST NOT fall back to an unbounded search. It SHALL instead:

- emit a **single** chunk when `count <= maxChunkUTF8` (which equals `2 * minChunkUTF8`, so every two-way split would undersize a side); or
- emit **three** chunks by balanced redistribution when `count >= 3 * minChunkUTF8`: split targets at `count / 3` and `2 * count / 3`, each moved to the nearest `Character` boundary with minimal deviation, ties resolving to the lower offset, so each chunk lands within `[minChunkUTF8, maxChunkUTF8]`; or
- when neither applies (`maxChunkUTF8 < count < 3 * minChunkUTF8`), emit two chunks split at the `Character` boundary in `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]` that minimizes the total shortfall below `minChunkUTF8`, ties resolving to the lower offset; or
- when even that range holds no `Character` boundary — a single grapheme cluster larger than `maxChunkUTF8` — emit the cluster **whole** as one oversized chunk, per the grapheme-first bounds requirement.

A split offset can never fall between a `\r` and a `\n`: `\r\n` is a single `Character` and every split offset is a `Character` boundary.

#### Scenario: Bidirectional search finds the boundary above the midpoint
- **WHEN** the midpoint of the window lands inside a multi-byte scalar whose preceding boundary is below `low` but whose following boundary is within the window
- **THEN** the split SHALL be taken at the following boundary, not at the preceding one

#### Scenario: Window with a single illegal offset yields three balanced chunks
- **WHEN** a 4096-byte slice is split and the window is the single offset 2048, which lies between a `\r` and a `\n`
- **THEN** the result SHALL be three chunks produced by balanced redistribution, each within `[minChunkUTF8, maxChunkUTF8]`, with the `\r\n` pair intact inside one of them

#### Scenario: Combination at or below the maximum is not split at all
- **WHEN** redistribution is attempted on a combined slice of at most `maxChunkUTF8` bytes
- **THEN** the result SHALL be a single chunk — the implementation SHALL NOT bisect a slice that already fits

#### Scenario: Split offset never separates CR from LF
- **WHEN** any slice containing `\r\n` is split by any code path
- **THEN** no resulting chunk SHALL end with `\r` while the next chunk begins with `\n`

## MODIFIED Requirements

### Requirement: Construction from String with chunk splitting
`TextRope.init(_ string:)` SHALL construct a balanced B-tree from the input string. The string SHALL be split into leaf chunks respecting `minChunkUTF8` (1024) and `maxChunkUTF8` (2048) byte boundaries as defined by the grapheme-first chunk-bounds requirement. Chunk splits MUST fall on `Character` boundaries only, so a `\r\n` sequence is never broken. Split point selection MUST use the same window-clamped bidirectional search as leaf splitting and redistribution: construction MUST NOT produce a leaf below `minChunkUTF8` when a `Character` boundary in the legal window would have avoided it, and MUST NOT split a grapheme cluster larger than `maxChunkUTF8` — such a cluster occupies one whole-cluster leaf. Leaves SHALL be grouped bottom-up in batches of `minChildren` to `maxChildren` to form inner nodes until a single root remains.

#### Scenario: Small string fits in a single leaf
- **WHEN** `TextRope("hello")` is constructed
- **THEN** the root SHALL be a leaf node with `chunk == "hello"` and correct summary

#### Scenario: Large string is split into multiple leaves
- **WHEN** a string larger than `maxChunkUTF8` is provided
- **THEN** the rope SHALL have multiple leaf nodes, each with chunk size between `minChunkUTF8` and `maxChunkUTF8` bytes

#### Scenario: CR-LF is not split across chunks
- **WHEN** a string contains `\r\n` near a chunk boundary
- **THEN** the `\r` and `\n` SHALL be in the same leaf chunk

#### Scenario: Empty string produces empty leaf root
- **WHEN** `TextRope("")` is constructed
- **THEN** the result SHALL be equivalent to `TextRope()` — an empty leaf root

#### Scenario: Multi-byte scalar at the greedy chunk boundary
- **WHEN** a string is constructed whose greedy chunk boundary at `maxChunkUTF8` falls inside a multi-byte scalar
- **THEN** the chunk SHALL end at the nearest `Character` boundary within the legal window, and no leaf SHALL fall below `minChunkUTF8` as a result
