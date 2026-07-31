## MODIFIED Requirements

### Requirement: Undersized leaf merging after delete
When a deletion causes a leaf's chunk to fall below `Node.minChunkUTF8` bytes, or leaves a `\r` at the end of one leaf and a `\n` at the start of the next, the affected leaves MUST be merged or have their content redistributed. Because every leaf holds at most `maxChunkUTF8` bytes, the combined slice is at most `2 * maxChunkUTF8` (4096) bytes. The outcome SHALL be determined by the combined size `count` and by the legal window `[low, high]`, where `low = max(minChunkUTF8, count - maxChunkUTF8)` and `high = min(maxChunkUTF8, count - minChunkUTF8)`:

- `count <= maxChunkUTF8` → the two leaves SHALL be merged into a **single** leaf.
- the window holds a `Character` boundary → the content SHALL be redistributed into **two** leaves, split at the boundary nearest `(count + 1) / 2` within the window, ties resolving to the lower offset. Both leaves SHALL be within `[minChunkUTF8, maxChunkUTF8]`.
- the window holds no `Character` boundary and `count >= 3 * minChunkUTF8` → the content SHALL be redistributed into **three** leaves, each within `[minChunkUTF8, maxChunkUTF8]`.
- otherwise (`maxChunkUTF8 < count < 3 * minChunkUTF8` with an empty window) → no shape satisfies both bounds. The content SHALL be split at the `Character` boundary within `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]` that minimizes the total shortfall below `minChunkUTF8`, ties resolving to the lower offset. No leaf SHALL exceed `maxChunkUTF8`; the resulting undersized leaf is permitted under the asymmetric chunk-size bounds.

Redistribution MUST respect UTF-8 character boundaries and the `\r\n` split invariant, and MUST NOT search outside the ranges named above. In particular, redistribution MUST NOT fall back to an unbounded backward walk from the midpoint.

#### Scenario: Leaf becomes undersized and merges with sibling
- **WHEN** a deletion reduces a leaf's chunk below `minChunkUTF8` bytes and the combined size with an adjacent sibling is ≤ `maxChunkUTF8`
- **THEN** the two leaves are merged into one leaf containing the concatenated content, the parent's child count decreases by one, and the merged leaf's summary is correct

#### Scenario: Leaf becomes undersized and redistributes with sibling
- **WHEN** a deletion reduces a leaf's chunk below `minChunkUTF8` bytes but merging with the adjacent sibling would exceed `maxChunkUTF8`
- **THEN** content is redistributed between the two leaves so both are above `minChunkUTF8`, both chunks contain valid UTF-8, and the `\r\n` split invariant is preserved

#### Scenario: Redistribution of a 2100-byte combination is balanced
- **WHEN** a 1200-byte leaf is reduced to 900 bytes and its 1200-byte sibling brings the combined size to 2100, with the window `[1024, 1076]` and no multi-byte characters
- **THEN** the result SHALL be exactly two leaves of 1050 bytes each

#### Scenario: CRLF rejoin of two full leaves yields three legal leaves
- **WHEN** a deletion removes the leaf between a 2048-byte leaf ending in `\r` and a 2048-byte leaf beginning with `\n`, so the combined 4096 bytes have their only window offset inside the `\r\n` pair
- **THEN** the result SHALL be three leaves, each between `minChunkUTF8` and `maxChunkUTF8` bytes, with `\r\n` intact inside one chunk
- **AND** no leaf SHALL be 2049 bytes or larger

#### Scenario: Unsatisfiable band keeps the maximum bound
- **WHEN** redistribution runs on a 2049-byte combined slice whose window `[1024, 1025]` is spanned by a single 4-byte scalar
- **THEN** the result SHALL be two leaves of 1023 and 1026 bytes — the shortfall-minimizing split — and repeating the same redistribution on that result SHALL reproduce the same shape without further change

#### Scenario: Deletion within a leaf that stays above minimum size
- **WHEN** a deletion reduces a leaf's chunk but it remains at or above `minChunkUTF8`
- **THEN** no merging or redistribution occurs — only the leaf's summary is updated

#### Scenario: Complete removal of a leaf
- **WHEN** a deletion removes all content from a leaf (its entire range is within the delete range)
- **THEN** the leaf is removed from the parent's children array and the parent handles the reduced child count
