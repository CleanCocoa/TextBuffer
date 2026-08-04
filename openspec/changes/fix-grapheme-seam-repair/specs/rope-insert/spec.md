## MODIFIED Requirements

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
