## MODIFIED Requirements

### Requirement: Undersized leaf merging after delete

> Generalized by `fix-grapheme-seam-repair` (DEF-016): the rejoin trigger covers **every** grapheme seam, with the `\r`/`\n` adjacency as the named special case — `\r\n` is a single Swift `Character`. Extended by `fix-delete-merge-starvation` (DEF-017): an undersized merge output is legal only when starved against **each** adjacent leaf in document order.

When a deletion causes a leaf's chunk to fall below `Node.minChunkUTF8` bytes, or leaves two adjacent leaves whose edge `Character`s join into a single grapheme cluster — the concatenation of the left leaf's last `Character` and the right leaf's first `Character` forms fewer than two `Character`s under Swift stdlib grapheme segmentation, of which a trailing `\r` before a leading `\n` is one instance — the affected leaves MUST be merged or have their content redistributed. Seam detection uses Swift `Character` segmentation only (the TextRope target is Foundation-free per ADR-013).

The seam-driven rejoin MUST fire **unconditionally** at every rejoin point the deletion touches: the check MUST NOT require that any leaf be undersized or that any child have been removed, because a deletion can expose a joining adjacency while every affected leaf stays within its byte bounds (for example deleting a base character whose combining mark starts the next leaf).

Because every conforming leaf holds at most `maxChunkUTF8` bytes, the combined slice is at most `2 * maxChunkUTF8` (4096) bytes plus at most one seam-adjacent whole-cluster leaf. The outcome SHALL be determined by the combined size `count` and by the legal window `[low, high]`, where `low = max(minChunkUTF8, count - maxChunkUTF8)` and `high = min(maxChunkUTF8, count - minChunkUTF8)`:

- `count <= maxChunkUTF8` → the two leaves SHALL be merged into a **single** leaf.
- the window holds a `Character` boundary → the content SHALL be redistributed into **two** leaves, split at the boundary nearest `(count + 1) / 2` within the window, ties resolving to the lower offset. Both leaves SHALL be within `[minChunkUTF8, maxChunkUTF8]`.
- the window holds no `Character` boundary and `count >= 3 * minChunkUTF8` → the content SHALL be redistributed into **three** leaves by balanced redistribution (targets at `count / 3` and `2 * count / 3`, each moved to the nearest `Character` boundary with minimal deviation), each within `[minChunkUTF8, maxChunkUTF8]`.
- otherwise (`maxChunkUTF8 < count < 3 * minChunkUTF8` with an empty window) → boundary starvation: no shape satisfies both bounds. The content SHALL be split at the `Character` boundary within `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]` that minimizes the total shortfall below `minChunkUTF8`, ties resolving to the lower offset. No leaf SHALL exceed `maxChunkUTF8` unless it is a single whole grapheme cluster; the resulting undersized leaf is permitted under the grapheme-first chunk-size bounds.

Every split point MUST fall on a `Character` boundary — never inside a grapheme cluster, not even at a Unicode scalar boundary — which preserves the `\r\n` invariant unconditionally and guarantees that a repaired seam cannot itself fall inside a cluster. Redistribution MUST NOT search outside the ranges named above; in particular it MUST NOT fall back to an unbounded backward walk from the midpoint.

A starved combination proves starvation only against **that pair**. An undersized chunk emitted by any merge combination is legal only under the per-adjacent-leaf starvation predicate (ADR-012, rope-core-types "Chunk size bounds are grapheme-first"): it MUST be starved against **each** leaf adjacent to it in document order — the flattened leaf sequence of the whole tree, whether or not the two leaves share a parent node. Therefore, when a combination's redistribution output contains an undersized chunk, the implementation MUST consult the other-side adjacent leaf — the neighbor on the side away from the pair that produced the chunk — and, when the combination with that neighbor admits a conforming redistribution (it is not boundary-starved under the same predicate the tree-invariant validator applies), redistribute the two so that both resulting leaves are within `[minChunkUTF8, maxChunkUTF8]`. The undersized chunk SHALL be accepted only when the other-side combination is itself boundary-starved (or no other-side leaf exists), at which point the leaf is provably starved against each adjacent leaf.

Because a deletion's touched leaf adjacencies all meet at inner nodes on the deletion path, the other-side consultation MUST reach adjacent leaves that lie under a **different parent**: an undersized edge leaf whose absorbing neighbor is the facing edge leaf of an adjacent subtree SHALL be detected at their common ancestor on the deletion path and repaired there — the parent boundary between two adjacent leaves is a grouping artifact and SHALL NOT limit the predicate.

Merges do not retry: a leaf that is out of bounds under proven boundary starvation is a fixed point. Subsequent merge scans MUST accept it without re-attempting redistribution, so repeated operations over the same shape neither oscillate nor re-run the failed split. This applies to seam-driven combinations exactly as to size-driven ones. The other-side consultation is a **single** additional redistribution attempt made when the undersized chunk is produced — it precedes fixed-point acceptance and does not constitute a retry: a successful attempt emits only conforming leaves (so it cannot cascade), and a failed attempt is the starvation proof for that side and is not repeated.

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

#### Scenario: Starved pair's undersized output is redistributed with the other-side neighbor
- **WHEN** a rope holds leaves of `[1074, 1024, 1034]` UTF-8 bytes — the third leaf beginning `"c"×7` then `\u{1F389}` — and a delete removes the last code unit of the middle leaf and the seven `c`s, so the middle pair's 2050-byte combination is starved (the `\u{1F389}` spans its `[1024, 1026]` window) and its minimal-shortfall split would emit a 1023-byte chunk, while the 1074-byte left neighbor's 2097-byte combination has `Character` boundaries throughout its `[1024, 1073]` window
- **THEN** the 1023-byte chunk SHALL NOT be accepted: it SHALL be redistributed with the left neighbor into two conforming leaves, and after the delete every leaf SHALL satisfy the chunk-size bounds — the tree-invariant validator SHALL report no chunk-size violation

#### Scenario: Other-side consultation reaches an absorbing neighbor under a different parent
- **WHEN** the same starved-pair shape arises with the undersized output at its parent's edge and the absorbing 1074-byte neighbor as the facing edge leaf of the adjacent subtree — e.g. a two-parent tree where the delete leaves the first child of the right parent at 1023 bytes, starved against its within-parent neighbor, while the left parent's last leaf could conformingly absorb it and neither parent falls below `minChildren`
- **THEN** the repair SHALL still occur — detected at the common ancestor on the deletion path — and no undersized leaf SHALL remain whose combination with **any** document-order adjacent leaf admits a conforming redistribution

#### Scenario: Undersized output starved against both adjacent leaves is a fixed point
- **WHEN** a starved pair's undersized output also has a boundary-starved combination with its other-side neighbor (e.g. leaves `[1026, 1024, 1034]` where the first leaf ends in `\u{1F389}` spanning the left combination's window, and the delete across the right seam produces the starved `[1023, 1027]` split)
- **THEN** the undersized leaf SHALL be accepted after the single other-side attempt fails — it is provably starved against each adjacent leaf — and subsequent operations SHALL neither oscillate its shape nor re-attempt the redistribution

#### Scenario: Deletion within a leaf that stays above minimum size
- **WHEN** a deletion reduces a leaf's chunk but it remains at or above `minChunkUTF8`, and the deletion exposes no grapheme seam at the leaf's edges
- **THEN** no merging or redistribution occurs — only the leaf's summary is updated

#### Scenario: Complete removal of a leaf
- **WHEN** a deletion removes all content from a leaf (its entire range is within the delete range)
- **THEN** the leaf is removed from the parent's children array and the parent handles the reduced child count
