## MODIFIED Requirements

### Requirement: Chunk size bounds are grapheme-first

Chunk-size bounds follow ADR-012's grapheme-first regime. Split points anywhere in the implementation — construction, leaf splitting on insert overflow, and redistribution during merges — MUST fall on `Character` (grapheme cluster) boundaries only. A split point MUST NOT fall inside a grapheme cluster, not even at a Unicode scalar boundary. Consequently the `\r\n` never-split rule is absolute rather than a special case: `\r\n` is a single `Character`.

The no-cluster-spans-a-seam invariant is a property of the **tree after every mutation**, not only of split-point selection. A seam-spanning cluster can form without any split point being chosen wrongly, by **adjacency change**: an insertion places content at a leaf edge whose new edge `Character` joins with the neighboring leaf's edge `Character` (for example a lone combining mark spliced at leaf-local offset 0), or a deletion removes the content that separated two leaves whose now-adjacent edge `Character`s join (for example deleting a base character whose combining mark starts the next leaf). After every `insert` and every `delete` — and by composition every `replace` — no grapheme cluster SHALL span a leaf seam: the implementation MUST repair any adjacency whose two edge `Character`s form a single `Character` when concatenated, by recombining the affected leaves at `Character` boundaries. The CRLF seam is one instance of this rule, not a separate mechanism.

Seam identification uses Swift stdlib grapheme segmentation (`Character`), the same segmentation used for split-point selection — NOT NSString composed-character-sequence semantics, whose parity machinery lives in the TextBuffer target per ADR-013's amendment.

A seam repair recombines existing content and is subject to the same bounds regime as any redistribution: its output MAY be a starvation-proven undersized leaf or a whole-cluster oversized leaf where the predicates below hold. The seam invariant is absolute; the byte bounds are not.

The byte bounds `[minChunkUTF8, maxChunkUTF8]` MUST hold for every leaf whenever a conforming `Character` boundary exists. They MAY be violated only under **boundary starvation** — when no `Character` boundary yields a conforming split — and then only minimally:

- A leaf's chunk MAY exceed `maxChunkUTF8` only when the chunk is a **single grapheme cluster** larger than `maxChunkUTF8`. The cluster occupies one whole-cluster leaf of whatever size it needs. There is no fixed byte cap on the excess and no scalar-boundary fallback.
- A leaf's chunk MAY fall below `minChunkUTF8` only when, for **each** adjacent leaf `S`, both of the following hold:
  - `leaf.chunk.utf8.count + S.chunk.utf8.count > maxChunkUTF8` — merging outright is impossible, and
  - the combined slice has no `Character` boundary at any UTF-8 offset in `[max(minChunkUTF8, count - maxChunkUTF8), min(maxChunkUTF8, count - minChunkUTF8)]` — redistribution to two conforming chunks is impossible.

**Adjacency in the starvation predicate is defined over the document-order leaf sequence** — the flattened in-order enumeration of every leaf in the tree. A leaf's adjacent leaves are its predecessor and successor in that sequence, **whether or not they share the leaf's parent node**: which inner node groups two adjacent leaves is a batching artifact and has no bearing on whether their bytes could be repartitioned conformingly. Producers MUST satisfy the predicate under this definition — an undersized leaf at its parent's edge whose document-order neighbor under an adjacent subtree could conformingly absorb it violates the bounds exactly as a same-parent shape does.

A rope whose entire content is smaller than `minChunkUTF8` is exempt: a single-leaf root has no size floor.

Starvation is provable per leaf from the tree alone, so tree-invariant validation MUST judge every out-of-bounds leaf against these exact predicates — no fuzzy tolerance constants, over document-order adjacency as defined above. A leaf that violates the bounds without satisfying its starvation predicate is a defect and MUST be reported. Seam validation has no starvation carve-out: a seam inside a grapheme cluster is unconditionally a violation.

#### Scenario: Split points never fall inside a grapheme cluster
- **WHEN** any leaf chunk is produced by construction, by a split on insert overflow, or by redistribution during a merge
- **THEN** every chunk SHALL begin and end on a `Character` boundary of the document — no grapheme cluster SHALL span a chunk seam

#### Scenario: Insert of a lone combining mark at a leaf boundary leaves no seam inside a cluster
- **WHEN** a rope holds `String(repeating: "a", count: 4096)` (leaves of 2048 and 2048 bytes) and `insert("\u{301}", at: 2048)` splices a combining acute at leaf-local offset 0 of the right leaf
- **THEN** after the insert, no grapheme cluster SHALL span any leaf seam — the cluster `a\u{301}` SHALL lie whole inside one leaf — and the rope's `content` and counts SHALL equal the oracle string's

#### Scenario: Deleting a base character does not expose a seam inside a cluster
- **WHEN** a rope holds `"a"×2048 + "b\u{301}" + "c"×2045` (leaves of 2048 and 2048 bytes) and `delete(in: 2048..<2049)` removes the base `b`, leaving a leaf ending in `a` adjacent to a leaf starting with `\u{301}`
- **THEN** the adjacency SHALL be repaired so that no grapheme cluster spans a leaf seam, even though neither leaf is below `minChunkUTF8`

#### Scenario: Seam repair outcomes are judged by the starvation predicates, not fixed byte ranges
- **WHEN** an adjacency repair recombines two leaves whose combined content admits no conforming two-way split
- **THEN** the repair MAY produce a starvation-proven undersized leaf or a whole-cluster oversized leaf, and validation SHALL accept exactly those shapes while still reporting any seam inside a cluster as a violation

#### Scenario: Oversized leaf is only permitted as a whole cluster
- **WHEN** a leaf's chunk exceeds `maxChunkUTF8` bytes
- **THEN** the chunk SHALL consist of exactly one grapheme cluster; an oversized chunk containing more than one `Character` is a violation

#### Scenario: Grapheme cluster larger than the maximum occupies one whole leaf
- **WHEN** the input contains a single grapheme cluster larger than `maxChunkUTF8` bytes (e.g. a long ZWJ chain or combining-mark run)
- **THEN** the entire cluster SHALL be stored in one leaf, unsplit, and validation SHALL accept that leaf

#### Scenario: Undersized leaf is only permitted when provably starved
- **WHEN** a leaf's chunk is below `minChunkUTF8` in a rope whose root is an inner node
- **THEN** for every adjacent leaf in the document-order leaf sequence — whether or not it shares the leaf's parent — the combined size SHALL exceed `maxChunkUTF8` **and** the combined slice SHALL have no `Character` boundary inside its legal redistribution window

#### Scenario: Two leaves that could merge are never left undersized
- **WHEN** a leaf is below `minChunkUTF8` and an adjacent leaf's chunk brings the combined size to at most `maxChunkUTF8`
- **THEN** the two SHALL have been merged into one leaf — leaving both is a violation

#### Scenario: A 2049-byte combination straddled by a 4-byte scalar
- **WHEN** two leaves are redistributed whose combined slice is 2049 UTF-8 bytes with a 4-byte scalar occupying bytes `[1023, 1027)`, so the window `[1024, 1025]` holds no `Character` boundary
- **THEN** the result SHALL be two leaves of 1023 and 1026 bytes — the minimal-deviation split — and the 1023-byte leaf SHALL be accepted by invariant validation under the starvation predicate above

#### Scenario: Single leaf below the floor is legal
- **WHEN** a rope's entire content is shorter than `minChunkUTF8`
- **THEN** the root SHALL be a single leaf holding all of it, and its size SHALL NOT be reported as a violation
