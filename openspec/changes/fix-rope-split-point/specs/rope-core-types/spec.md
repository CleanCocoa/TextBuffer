## ADDED Requirements

### Requirement: Chunk size bounds are asymmetric

`Node.maxChunkUTF8` SHALL be a hard upper bound and `Node.minChunkUTF8` a best-effort lower bound. Every split point chosen anywhere in the implementation — construction, leaf splitting on insert overflow, and redistribution during merges — MUST honor this contract.

A leaf's chunk MUST NOT exceed `maxChunkUTF8` bytes. It MAY exceed it only when no Unicode scalar boundary exists at any UTF-8 offset in `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]` of the slice being split — that is, when a single grapheme cluster is larger than `maxChunkUTF8` bytes. In that case the excess MUST be at most 3 bytes, because Unicode scalar boundaries are at most 4 UTF-8 bytes apart.

A leaf's chunk SHOULD be at least `minChunkUTF8` bytes. It MAY fall below `minChunkUTF8` only when, for **each** adjacent sibling leaf `S`, both of the following hold:

- `leaf.chunk.utf8.count + S.chunk.utf8.count > maxChunkUTF8` — merging outright is impossible, and
- the combined slice has no `Character` boundary at any UTF-8 offset in `[max(minChunkUTF8, count - maxChunkUTF8), min(maxChunkUTF8, count - minChunkUTF8)]` — redistribution to two legal chunks is impossible.

A rope whose entire content is smaller than `minChunkUTF8` is exempt: a single-leaf root has no size floor.

Because both conditions are decidable from the tree alone, an undersized leaf that does **not** satisfy them is a defect and MUST be reported by tree-invariant validation rather than tolerated.

#### Scenario: Split points never produce an oversized chunk
- **WHEN** any leaf chunk is produced by construction, by a split on insert overflow, or by redistribution during a merge
- **THEN** its UTF-8 byte count SHALL be at most `maxChunkUTF8`, unless a single grapheme cluster larger than `maxChunkUTF8` forces the excess, in which case the excess SHALL be at most 3 bytes

#### Scenario: Undersized leaf is only permitted when provably unavoidable
- **WHEN** a leaf's chunk is below `minChunkUTF8` in a rope whose root is an inner node
- **THEN** for every adjacent sibling leaf, the combined size SHALL exceed `maxChunkUTF8` **and** the combined slice SHALL have no `Character` boundary inside its legal redistribution window

#### Scenario: Two leaves that could merge are never left undersized
- **WHEN** a leaf is below `minChunkUTF8` and an adjacent sibling's chunk brings the combined size to at most `maxChunkUTF8`
- **THEN** the two SHALL have been merged into one leaf — leaving both is a violation

#### Scenario: A 2049-byte combination straddled by a 4-byte scalar
- **WHEN** two leaves are redistributed whose combined slice is 2049 UTF-8 bytes with a 4-byte scalar occupying bytes `[1023, 1027)`, so the window `[1024, 1025]` holds no `Character` boundary
- **THEN** the result SHALL be two leaves of 1023 and 1026 bytes — no three-leaf shape can satisfy the lower bound at that size, and the 1023-byte leaf SHALL be accepted by invariant validation under the carve-out above

#### Scenario: Single leaf below the floor is legal
- **WHEN** a rope's entire content is shorter than `minChunkUTF8`
- **THEN** the root SHALL be a single leaf holding all of it, and its size SHALL NOT be reported as a violation

### Requirement: Split point selection is clamped to the legal window

When a slice of `count` UTF-8 bytes is split into two chunks, the split offset MUST fall within `[low, high]` where `low = max(minChunkUTF8, count - maxChunkUTF8)` and `high = min(maxChunkUTF8, count - minChunkUTF8)`, whenever that window is non-empty and contains a `Character` boundary. The search MUST proceed in **both** directions from the midpoint `(count + 1) / 2` and MUST NOT walk past either end of the window; ties SHALL resolve to the lower offset.

When the window contains no `Character` boundary the implementation MUST NOT fall back to an unbounded search. It SHALL instead:

- emit a **single** chunk when `count <= maxChunkUTF8` (which equals `2 * minChunkUTF8`, so every two-way split would undersize a side); or
- emit **three** chunks, each within `[minChunkUTF8, maxChunkUTF8]`, when `count >= 3 * minChunkUTF8`; or
- when neither applies (`maxChunkUTF8 < count < 3 * minChunkUTF8`), emit two chunks split at the `Character` boundary in `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]` that minimizes the total shortfall below `minChunkUTF8`, ties resolving to the lower offset.

A split offset MUST never fall between a `\r` and a `\n`. This holds automatically for `Character`-boundary offsets; the scalar-boundary escape hatch of the asymmetric-bounds requirement MUST exclude that offset explicitly.

#### Scenario: Bidirectional search finds the boundary above the midpoint
- **WHEN** the midpoint of the window lands inside a multi-byte scalar whose preceding boundary is below `low` but whose following boundary is within the window
- **THEN** the split SHALL be taken at the following boundary, not at the preceding one

#### Scenario: Window with a single illegal offset yields three chunks
- **WHEN** a 4096-byte slice is split and the window is the single offset 2048, which lies between a `\r` and a `\n`
- **THEN** the result SHALL be three chunks, each within `[minChunkUTF8, maxChunkUTF8]`, with the `\r\n` pair intact inside one of them

#### Scenario: Combination at or below the maximum is not split at all
- **WHEN** redistribution is attempted on a combined slice of at most `maxChunkUTF8` bytes
- **THEN** the result SHALL be a single chunk — the implementation SHALL NOT bisect a slice that already fits

#### Scenario: Split offset never separates CR from LF
- **WHEN** any slice containing `\r\n` is split by any code path
- **THEN** no resulting chunk SHALL end with `\r` while the next chunk begins with `\n`

## MODIFIED Requirements

### Requirement: Construction from String with chunk splitting
`TextRope.init(_ string:)` SHALL construct a balanced B-tree from the input string. The string SHALL be split into leaf chunks respecting `minChunkUTF8` (1024) and `maxChunkUTF8` (2048) byte boundaries as defined by the asymmetric-bounds requirement. Chunk splits MUST NOT break a `\r\n` sequence — if the byte before a split point is `\r` and the byte after is `\n`, the split point SHALL be adjusted to keep them together. Split point selection MUST use the same window-clamped bidirectional search as leaf splitting and redistribution: construction MUST NOT produce a leaf below `minChunkUTF8` when a `Character` boundary in the legal window would have avoided it. Leaves SHALL be grouped bottom-up in batches of `minChildren` to `maxChildren` to form inner nodes until a single root remains.

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
