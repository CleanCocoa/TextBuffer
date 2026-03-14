## ADDED Requirements

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
`TextRope.init(_ string:)` SHALL construct a balanced B-tree from the input string. The string SHALL be split into leaf chunks respecting `minChunkUTF8` (1024) and `maxChunkUTF8` (2048) byte boundaries. Chunk splits MUST NOT break a `\r\n` sequence — if the byte before a split point is `\r` and the byte after is `\n`, the split point SHALL be adjusted to keep them together. Leaves SHALL be grouped bottom-up in batches of `minChildren` to `maxChildren` to form inner nodes until a single root remains.

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
