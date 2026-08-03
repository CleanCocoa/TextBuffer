# rope-core-types Specification

## Purpose
TBD - created by archiving change m2-rope-foundation. Update Purpose after archive.
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
`TextRope` SHALL conform to `Equatable`. Two TextRope values SHALL be equal if and only if their `content` strings are equal.

#### Scenario: Two ropes with the same content are equal
- **WHEN** two `TextRope` values are constructed from the same string
- **THEN** they SHALL be equal (`==` returns `true`)

#### Scenario: Two ropes with different content are not equal
- **WHEN** two `TextRope` values hold different strings
- **THEN** they SHALL NOT be equal (`==` returns `false`)

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

