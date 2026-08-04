## MODIFIED Requirements

### Requirement: Undersized leaf merging after delete

> Generalized by `fix-grapheme-seam-repair` (DEF-016): the rejoin trigger covers **every** grapheme seam, with the `\r`/`\n` adjacency as the named special case — `\r\n` is a single Swift `Character`.

When a deletion causes a leaf's chunk to fall below `Node.minChunkUTF8` bytes, or leaves two adjacent leaves whose edge `Character`s join into a single grapheme cluster — the concatenation of the left leaf's last `Character` and the right leaf's first `Character` forms fewer than two `Character`s under Swift stdlib grapheme segmentation, of which a trailing `\r` before a leading `\n` is one instance — the affected leaves MUST be merged or have their content redistributed. Seam detection uses Swift `Character` segmentation only (the TextRope target is Foundation-free per ADR-013).

The seam-driven rejoin MUST fire **unconditionally** at every rejoin point the deletion touches: the check MUST NOT require that any leaf be undersized or that any child have been removed, because a deletion can expose a joining adjacency while every affected leaf stays within its byte bounds (for example deleting a base character whose combining mark starts the next leaf).

Because every conforming leaf holds at most `maxChunkUTF8` bytes, the combined slice is at most `2 * maxChunkUTF8` (4096) bytes plus at most one seam-adjacent whole-cluster leaf. The outcome SHALL be determined by the combined size `count` and by the legal window `[low, high]`, where `low = max(minChunkUTF8, count - maxChunkUTF8)` and `high = min(maxChunkUTF8, count - minChunkUTF8)`:

- `count <= maxChunkUTF8` → the two leaves SHALL be merged into a **single** leaf.
- the window holds a `Character` boundary → the content SHALL be redistributed into **two** leaves, split at the boundary nearest `(count + 1) / 2` within the window, ties resolving to the lower offset. Both leaves SHALL be within `[minChunkUTF8, maxChunkUTF8]`.
- the window holds no `Character` boundary and `count >= 3 * minChunkUTF8` → the content SHALL be redistributed into **three** leaves by balanced redistribution (targets at `count / 3` and `2 * count / 3`, each moved to the nearest `Character` boundary with minimal deviation), each within `[minChunkUTF8, maxChunkUTF8]`.
- otherwise (`maxChunkUTF8 < count < 3 * minChunkUTF8` with an empty window) → boundary starvation: no shape satisfies both bounds. The content SHALL be split at the `Character` boundary within `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]` that minimizes the total shortfall below `minChunkUTF8`, ties resolving to the lower offset. No leaf SHALL exceed `maxChunkUTF8` unless it is a single whole grapheme cluster; the resulting undersized leaf is permitted under the grapheme-first chunk-size bounds.

Every split point MUST fall on a `Character` boundary — never inside a grapheme cluster, not even at a Unicode scalar boundary — which preserves the `\r\n` invariant unconditionally and guarantees that a repaired seam cannot itself fall inside a cluster. Redistribution MUST NOT search outside the ranges named above; in particular it MUST NOT fall back to an unbounded backward walk from the midpoint.

Merges do not retry: a leaf that is out of bounds under proven boundary starvation is a fixed point. Subsequent merge scans MUST accept it without re-attempting redistribution, so repeated operations over the same shape neither oscillate nor re-run the failed split. This applies to seam-driven combinations exactly as to size-driven ones.

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
- **THEN** the result SHALL be three leaves produced by balanced redistribution, each between `minChunkUTF8` and `maxChunkUTF8` bytes, with `\r\n` intact inside one chunk
- **AND** no leaf SHALL be 2049 bytes or larger

#### Scenario: Deleting a base character rejoins the exposed grapheme seam without a size trigger
- **WHEN** a rope holds `"a"×2048 + "b\u{301}" + "c"×2045` (leaves of 2048 and 2048 bytes) and `delete(in: 2048..<2049)` removes the base `b`, leaving a 2048-byte leaf ending in `a` adjacent to a 2047-byte leaf starting with `\u{301}` — neither leaf undersized, no child removed
- **THEN** the rejoin SHALL still fire: after the delete, no grapheme cluster SHALL span any leaf seam, and `content` and counts SHALL match the oracle

#### Scenario: Rejoin check runs at every touched adjacency regardless of chunk sizes
- **WHEN** a deletion changes the edge `Character` of a leaf, or removes children so that two previously separated leaves become adjacent, while every affected leaf stays within `[minChunkUTF8, maxChunkUTF8]`
- **THEN** each touched adjacency SHALL be checked for a joining grapheme pair and repaired when one is found

#### Scenario: Starved band takes the minimal-deviation split
- **WHEN** redistribution runs on a 2049-byte combined slice whose window `[1024, 1025]` is spanned by a single 4-byte scalar
- **THEN** the result SHALL be two leaves of 1023 and 1026 bytes — the shortfall-minimizing split among the available `Character` boundaries

#### Scenario: Starved leaf is accepted without a merge retry
- **WHEN** subsequent operations traverse a leaf that is undersized under proven boundary starvation (e.g. the 1023-byte leaf of the previous scenario)
- **THEN** the merge scan SHALL accept the leaf as-is — re-running the same merge on the same pair SHALL reproduce the identical shape, with no repeated redistribution attempt

#### Scenario: Deletion within a leaf that stays above minimum size
- **WHEN** a deletion reduces a leaf's chunk but it remains at or above `minChunkUTF8`, and the deletion exposes no grapheme seam at the leaf's edges
- **THEN** no merging or redistribution occurs — only the leaf's summary is updated

#### Scenario: Complete removal of a leaf
- **WHEN** a deletion removes all content from a leaf (its entire range is within the delete range)
- **THEN** the leaf is removed from the parent's children array and the parent handles the reduced child count
