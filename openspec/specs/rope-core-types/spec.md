# rope-core-types Specification

## Purpose
Defines the foundational types and invariants everything else in the rope builds on: the internal `Summary` (cached UTF-8 byte, UTF-16 code unit, and line counts) and B-tree `Node` (leaves holding grapheme-first bounded chunks, inner nodes with bounded child counts), and the public `TextRope` value type built on them — always rooted, `Sendable`, `Equatable` by content with an O(1) summary early-out, and copy-on-write via path-copying so copies share structure until mutated, a guarantee that must hold under concurrent mutation from many tasks. Construction from a `String` produces a balanced tree whose split points fall only on `Character` boundaries within the window-clamped chunk-size bounds (so `\r\n` pairs and grapheme clusters are never split), and the root summary makes length queries O(1).
## Requirements
### Requirement: Summary tracks utf8, utf16, and line counts
`TextRope.Summary` SHALL be an internal value type with three integer fields: `utf8` (byte count), `utf16` (UTF-16 code unit count), and `lines` (newline count). It SHALL provide a `zero` static constant, `add(_:)` and `subtract(_:)` mutating methods for combining summaries, and a `of(_:)` static factory that computes metrics from a `String`.

#### Scenario: Summary.of computes correct metrics for ASCII string
- **WHEN** `Summary.of("hello\nworld")` is called
- **THEN** the result SHALL have `utf8 == 11`, `utf16 == 11`, `lines == 1`

#### Scenario: Summary.of computes correct metrics for multi-byte characters
- **WHEN** `Summary.of` is called with a string containing characters above U+FFFF (e.g., emoji 🎉 which is 4 UTF-8 bytes and 2 UTF-16 code units)
- **THEN** `utf8` SHALL reflect the total UTF-8 byte count, `utf16` SHALL reflect the total UTF-16 code unit count (including surrogate pairs), and `lines` SHALL count only `\n` bytes

#### Scenario: Summary.zero has all fields at zero
- **WHEN** `Summary.zero` is accessed
- **THEN** `utf8 == 0`, `utf16 == 0`, `lines == 0`

#### Scenario: Summary add and subtract are inverse operations
- **WHEN** summary A is added to summary B, then B is subtracted from the result
- **THEN** the result SHALL equal summary A

### Requirement: Node represents B-tree leaf and inner nodes
`TextRope.Node` SHALL be an internal reference type (`final class`) with: a `summary` of type `Summary`, a `height` (`UInt8`, 0 for leaves), a `chunk` (`String`, non-empty for leaves, empty for inner nodes), and `children` (`ContiguousArray<Node>`, empty for leaves, non-empty for inner nodes). Node SHALL define branching constants `maxChildren` (8) and `minChildren` (4), and chunk size constants `maxChunkUTF8` (2048) and `minChunkUTF8` (1024).

#### Scenario: Leaf node has height zero and no children
- **WHEN** a leaf Node is created with a text chunk
- **THEN** `height` SHALL be 0, `children` SHALL be empty, `chunk` SHALL contain the text, and `summary` SHALL equal `Summary.of(chunk)`

#### Scenario: Inner node has positive height and no chunk
- **WHEN** an inner Node is created with child nodes
- **THEN** `height` SHALL be greater than 0, `chunk` SHALL be empty, `children` SHALL be non-empty, and `summary` SHALL equal the combined summaries of all children

#### Scenario: Node provides an empty leaf factory
- **WHEN** `Node.emptyLeaf()` is called
- **THEN** it SHALL return a leaf node with an empty chunk, height 0, and `Summary.zero`

### Requirement: Node is a pure Swift class
`Node` MUST NOT inherit from `NSObject` or any Objective-C base class. It MUST be a pure Swift `final class` so that `isKnownUniquelyReferenced` functions correctly.

#### Scenario: isKnownUniquelyReferenced works on Node
- **WHEN** a single strong reference to a Node exists and `isKnownUniquelyReferenced` is called
- **THEN** it SHALL return `true`

#### Scenario: Shared Node is detected
- **WHEN** two strong references to the same Node exist and `isKnownUniquelyReferenced` is called on one
- **THEN** it SHALL return `false`

### Requirement: COW path-copying via shallowCopy
`Node.shallowCopy()` SHALL return a new Node with the same `summary`, `height`, `chunk`, and `children` references. It SHALL NOT deep-copy child subtrees — children are shared by reference until they are themselves mutated.

#### Scenario: shallowCopy creates a distinct object with shared children
- **WHEN** `shallowCopy()` is called on an inner node with N children
- **THEN** the returned node SHALL be a different object (`!==` original) with identical summary, height, and the same child references (`===` each child)

### Requirement: ensureUniqueChild uses extract-check-write-back pattern
`Node.ensureUniqueChild(at:)` SHALL ensure the child at the given index is uniquely referenced. If the child is shared, it SHALL be replaced with a shallow copy. The method SHALL use the extract→check→write-back pattern required by `isKnownUniquelyReferenced` on array elements.

#### Scenario: Unique child is not copied
- **WHEN** `ensureUniqueChild(at:)` is called and the child at that index has only one strong reference (via the parent's children array)
- **THEN** the child reference SHALL remain the same object (`===`)

#### Scenario: Shared child is replaced with a copy
- **WHEN** an external reference to a child exists and `ensureUniqueChild(at:)` is called for that index
- **THEN** the child at that index SHALL be replaced with a new object (`!==` original) that has the same summary and children references

### Requirement: TextRope is always-rooted
`TextRope` SHALL always hold a non-optional `root: Node`. An empty `TextRope` SHALL have an empty leaf node as its root — the root is never nil. `isEmpty` SHALL return `true` when `root.summary.utf8 == 0`.

#### Scenario: Default-initialized TextRope has an empty leaf root
- **WHEN** `TextRope()` is created
- **THEN** `isEmpty` SHALL be `true`, `utf8Count` SHALL be 0, `utf16Count` SHALL be 0, and `content` SHALL be `""`

#### Scenario: TextRope root is never nil
- **WHEN** any `TextRope` value exists (empty or non-empty)
- **THEN** the internal `root` property SHALL be a valid Node (never nil)

### Requirement: TextRope has value semantics with COW
`TextRope` SHALL be a value type (`struct`) with copy-on-write semantics. `ensureUnique()` SHALL check `isKnownUniquelyReferenced(&root)` and replace root with `root.shallowCopy()` if shared. Copying a `TextRope` SHALL share the root node; subsequent mutation of either copy SHALL NOT affect the other.

#### Scenario: Copied TextRope shares root until mutation
- **WHEN** `var b = a` copies a TextRope and then `a` is not mutated
- **THEN** both `a` and `b` SHALL have identical content

#### Scenario: Mutation after copy does not affect the original
- **WHEN** `var b = a` copies a TextRope and then `b` is mutated (in future operations)
- **THEN** `a.content` SHALL remain unchanged

#### Scenario: ensureUnique on uniquely-held root does not copy
- **WHEN** `ensureUnique()` is called on a TextRope with a uniquely-referenced root
- **THEN** the root reference SHALL remain the same object

### Requirement: TextRope is Sendable
`TextRope` SHALL conform to `Sendable`. The root node reference SHALL be declared `nonisolated(unsafe)` because Node itself is not Sendable, but the value-type wrapper guarantees exclusive access.

#### Scenario: TextRope can be passed across isolation boundaries
- **WHEN** a `TextRope` value is assigned to a `Sendable`-requiring context
- **THEN** the compiler SHALL accept it without warnings

### Requirement: TextRope is Equatable via content comparison

> Rebased on the `fix-rope-cow-and-equality-coverage` delta for this requirement, which lands first. This version carries that delta's text forward and adds the tiered summary early-out; it does not replace its coverage obligations.

`TextRope` SHALL conform to `Equatable`. Two TextRope values SHALL be equal if and only if their `content` strings are equal. Equality SHALL be independent of tree shape: two ropes holding the same characters over different leaf partitions, different child groupings, or different heights SHALL compare equal — no term of the comparison may be shape-derived.

Equality SHALL be decided in three tiers, in order:

1. **Identity.** If both values share the same root node (`lhs.root === rhs.root`), they SHALL be equal without further work.
2. **Summary early-out.** Otherwise, if the two root summaries differ in any field (`utf8`, `utf16`, or `lines`), the values SHALL be unequal. This comparison MUST be O(1) and MUST NOT materialize either rope's content.
3. **Content comparison.** Otherwise, equality SHALL be decided by comparing the materialized `content` strings.

Tier 2 is sound because every `Summary` field is a pure, additive function of the text: `utf8` is its UTF-8 byte count, `utf16` its UTF-16 code unit count, and `lines` its `\n` count. A node's summary equals the sum over its subtree, so the root summary equals that same function applied to `content`. Equal content therefore implies equal summaries, and — by contraposition — differing summaries prove differing content.

The converse does NOT hold: equal summaries do NOT imply equal content, since distinct texts can share all three counts (for example `"ab"` and `"ba"`). Tier 3 is therefore mandatory and MUST NOT be elided; an implementation that returns `true` on matching summaries alone violates this requirement.

This conformance SHALL be covered by tests in `Tests/TextRopeTests/TextRopeEqualityTests.swift` — the file established by `fix-rope-cow-and-equality-coverage`, which the summary-early-out cases extend rather than recreate. Coverage MUST NOT be claimed by a task checkbox without a rope-to-rope equality assertion existing in the suite.

#### Scenario: Two ropes with the same content are equal

- **WHEN** two `TextRope` values are constructed from the same string
- **THEN** they SHALL be equal (`==` returns `true`), pinned by `testRopesWithSameContentAreEqual`

#### Scenario: Same content over different tree shapes is equal

- **WHEN** one rope is built by a single `TextRope(_:)` construction and another rope holding identical content is assembled by incremental `insert` calls that produce a demonstrably different leaf partition
- **THEN** the two ropes SHALL be equal, pinned by `testRopesWithSameContentButDifferentTreeShapesAreEqual`, which SHALL first assert that the two leaf partitions actually differ

#### Scenario: Two ropes with different content are not equal

- **WHEN** two `TextRope` values hold different strings
- **THEN** they SHALL NOT be equal (`==` returns `false`), pinned by `testRopesWithDifferentContentAreNotEqual`

#### Scenario: Differing summaries decide inequality without materializing content

- **WHEN** two ropes differ in UTF-8 byte count, UTF-16 code unit count, or newline count
- **THEN** `==` SHALL return `false` in constant time, without building either rope's `content` string

#### Scenario: Identical UTF-16 length with differing byte count is rejected early

- **WHEN** two ropes have the same UTF-16 code unit count but different UTF-8 byte counts (for example one containing a multi-byte character where the other holds ASCII)
- **THEN** `==` SHALL return `false` via the summary early-out

#### Scenario: Same length but different content is not equal

- **WHEN** two `TextRope` values hold different strings with identical UTF-8 byte counts, UTF-16 code unit counts, and newline counts
- **THEN** they SHALL NOT be equal, pinned by `testRopesWithSameUTF16CountButDifferentContentAreNotEqual` — a summary-based early-out MUST NOT be able to satisfy this scenario by comparing summaries alone

#### Scenario: Equal summaries still require content comparison

- **WHEN** two ropes have identical `utf8`, `utf16`, and `lines` summaries but different text — the single-leaf case pinned by `testRopesWithSameUTF16CountButDifferentContentAreNotEqual`, and a multi-leaf case whose bytes are permuted across leaf boundaries
- **THEN** `==` SHALL return `false` — the early-out MUST NOT treat matching summaries as proof of equality

#### Scenario: Empty ropes are equal

- **WHEN** `TextRope()` is compared with `TextRope("")`
- **THEN** they SHALL be equal, pinned by `testEmptyRopesAreEqual`

#### Scenario: Reference-identical roots take the identity fast path

- **WHEN** a `TextRope` is copied and neither copy is mutated, so both share the same root node
- **THEN** the two values SHALL be equal without comparing summaries or content, and the shared-root precondition SHALL be asserted, pinned by `testCopyWithSharedRootIsEqual`

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

### Requirement: Content materialization returns full text
`TextRope.content` SHALL return the full text by concatenating all leaf chunks via in-order traversal. The result SHALL be identical to the string used to construct the rope.

#### Scenario: Round-trip construction and materialization
- **WHEN** `TextRope(s).content` is evaluated for any string `s`
- **THEN** the result SHALL equal `s`

#### Scenario: Empty rope content is empty string
- **WHEN** `TextRope().content` is evaluated
- **THEN** the result SHALL be `""`

### Requirement: utf8Count and utf16Count are O(1) from root summary
`TextRope.utf8Count` SHALL return `root.summary.utf8` and `TextRope.utf16Count` SHALL return `root.summary.utf16`. Both SHALL be O(1) operations.

#### Scenario: Counts match String properties after construction
- **WHEN** a `TextRope` is constructed from a string `s`
- **THEN** `utf8Count` SHALL equal `s.utf8.count` and `utf16Count` SHALL equal `s.utf16.count`

### Requirement: Chunk size bounds are grapheme-first

Chunk-size bounds follow ADR-012's grapheme-first regime. Split points anywhere in the implementation — construction, leaf splitting on insert overflow, and redistribution during merges — MUST fall on `Character` (grapheme cluster) boundaries only. A split point MUST NOT fall inside a grapheme cluster, not even at a Unicode scalar boundary. Consequently the `\r\n` never-split rule is absolute rather than a special case: `\r\n` is a single `Character`.

The no-cluster-spans-a-seam invariant is a property of the **tree after every mutation**, not only of split-point selection. A seam-spanning cluster can form without any split point being chosen wrongly, by **adjacency change**: an insertion places content at a leaf edge whose new edge `Character` joins with the neighboring leaf's edge `Character` (for example a lone combining mark spliced at leaf-local offset 0), or a deletion removes the content that separated two leaves whose now-adjacent edge `Character`s join (for example deleting a base character whose combining mark starts the next leaf). After every `insert` and every `delete` — and by composition every `replace` — no grapheme cluster SHALL span a leaf seam: the implementation MUST repair any adjacency whose two edge `Character`s form a single `Character` when concatenated, by recombining the affected leaves at `Character` boundaries. The CRLF seam is one instance of this rule, not a separate mechanism.

Seam identification uses Swift stdlib grapheme segmentation (`Character`), the same segmentation used for split-point selection — NOT NSString composed-character-sequence semantics, whose parity machinery lives in the TextBuffer target per ADR-013's amendment.

A seam repair recombines existing content and is subject to the same bounds regime as any redistribution: its output MAY be a starvation-proven undersized leaf or a whole-cluster oversized leaf where the predicates below hold. The seam invariant is absolute; the byte bounds are not.

The byte bounds `[minChunkUTF8, maxChunkUTF8]` MUST hold for every leaf whenever a conforming `Character` boundary exists. They MAY be violated only under **boundary starvation** — when no `Character` boundary yields a conforming split — and then only minimally:

- A leaf's chunk MAY exceed `maxChunkUTF8` only when the chunk is a **single grapheme cluster** larger than `maxChunkUTF8`. The cluster occupies one whole-cluster leaf of whatever size it needs. There is no fixed byte cap on the excess and no scalar-boundary fallback.
- A leaf's chunk MAY fall below `minChunkUTF8` only when, for **each** adjacent sibling leaf `S`, both of the following hold:
  - `leaf.chunk.utf8.count + S.chunk.utf8.count > maxChunkUTF8` — merging outright is impossible, and
  - the combined slice has no `Character` boundary at any UTF-8 offset in `[max(minChunkUTF8, count - maxChunkUTF8), min(maxChunkUTF8, count - minChunkUTF8)]` — redistribution to two conforming chunks is impossible.

A rope whose entire content is smaller than `minChunkUTF8` is exempt: a single-leaf root has no size floor.

Starvation is provable per leaf from the tree alone, so tree-invariant validation MUST judge every out-of-bounds leaf against these exact predicates — no fuzzy tolerance constants. A leaf that violates the bounds without satisfying its starvation predicate is a defect and MUST be reported. Seam validation has no starvation carve-out: a seam inside a grapheme cluster is unconditionally a violation.

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

### Requirement: TextRope value semantics hold under concurrent mutation

`TextRope` is `Sendable` over a `nonisolated(unsafe) var root: Node` whose element type is not `Sendable`. The safety of that declaration rests entirely on copy-on-write path-copying, so the guarantee SHALL be verified concurrently and not only single-threaded.

When a single `TextRope` value is shared with many concurrently executing tasks and each task takes its own copy and mutates it, every task SHALL observe only the effect of its own mutation, and the shared original SHALL be unchanged after all tasks complete. The verification MUST use a height-3 template — leaves under two levels of inner nodes — so that `Node.ensureUniqueChild(at:)` is exercised concurrently at more than one depth on genuinely shared children. A single-leaf template only exercises `TextRope.ensureUnique()` at the root and proves nothing about path-copying below it.

Each task's copy MUST be taken inside the concurrently executing task body, not in the spawning loop, so that the copy and the subsequent uniqueness checks actually run in parallel against the same shared nodes.

#### Scenario: Parallel mutations from a shared multi-level rope are independent

- **WHEN** a `TextRope` whose root is an inner node of height 3 is shared with many concurrent tasks, and each task copies it and mutates at its own distinct UTF-16 offset
- **THEN** each task's result SHALL equal the result of applying only its own mutation to the template content, verified against a `String` oracle
- **AND** the template's `content` SHALL be unchanged after every task completes

#### Scenario: Concurrent buffer mutations from a multi-level template are independent

- **WHEN** a `SendableRopeBuffer` backed by a multi-leaf, height-3 rope is shared with many concurrent tasks, and each task copies it and replaces a distinct range
- **THEN** each task's buffer content SHALL reflect only its own replacement, and the shared template SHALL be unchanged

#### Scenario: Concurrency coverage is not degenerate

- **WHEN** the concurrent value-semantics tests run
- **THEN** they SHALL assert the template's tree shape (height 3: multiple leaves under two levels of inner nodes) before fanning out, so that a future chunking or branching change cannot silently reduce the coverage to a shallower case

