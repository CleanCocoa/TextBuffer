## ADDED Requirements

### Requirement: Delete a UTF-16 range
The `TextRope` type SHALL provide a `mutating func delete(in utf16Range: NSRange)` method that removes the content within the specified UTF-16 code unit range. The range MUST be within `0..<utf16Count` (location + length ≤ utf16Count). After deletion, the rope's `utf16Count` SHALL equal the previous `utf16Count` minus the deleted range's length. The rope's `content` SHALL equal the original content with the specified range removed.

#### Scenario: Delete from a single-leaf rope
- **WHEN** a rope contains `"hello world"` and `delete(in: NSRange(location: 5, length: 6))` is called
- **THEN** `content` is `"hello"` and `utf16Count` is `5`

#### Scenario: Delete at the beginning
- **WHEN** a rope contains `"hello world"` and `delete(in: NSRange(location: 0, length: 6))` is called
- **THEN** `content` is `"world"`

#### Scenario: Delete at the end
- **WHEN** a rope contains `"hello world"` and `delete(in: NSRange(location: 5, length: 6))` is called
- **THEN** `content` is `"hello"`

#### Scenario: Delete in the middle
- **WHEN** a rope contains `"hello world"` and `delete(in: NSRange(location: 2, length: 6))` is called
- **THEN** `content` is `"herld"`

#### Scenario: Delete empty range is a no-op
- **WHEN** `delete(in: NSRange(location: 3, length: 0))` is called on a rope containing `"hello"`
- **THEN** `content` remains `"hello"` and the tree structure is unchanged

#### Scenario: Delete with multi-byte characters
- **WHEN** a rope contains `"café🎉"` (UTF-16 length 6) and `delete(in: NSRange(location: 4, length: 2))` is called
- **THEN** `content` is `"café"` and `utf16Count` is `4` (emoji was 2 UTF-16 code units)

#### Scenario: Delete spanning a surrogate pair boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16: `a`, high surrogate, low surrogate, `b` — length 4) and `delete(in: NSRange(location: 1, length: 2))` is called
- **THEN** `content` is `"ab"` — the entire emoji is removed

### Requirement: Delete spanning multiple leaves
When the UTF-16 range spans multiple leaves in the rope tree, the delete operation SHALL correctly remove content across all affected leaves. The start leaf SHALL lose its suffix from the start offset onward. Intermediate leaves SHALL be removed entirely. The end leaf SHALL lose its prefix up to the end offset. The resulting tree MUST remain structurally valid with correct summaries.

#### Scenario: Delete spanning two leaves
- **WHEN** a multi-leaf rope has content distributed across at least two leaves, and a delete range spans from the middle of the first leaf to the middle of the second leaf
- **THEN** the affected content is removed, the remaining content is correct, and `utf16Count` reflects the deletion

#### Scenario: Delete spanning an entire subtree
- **WHEN** a delete range encompasses all content in one or more intermediate children of an inner node
- **THEN** those children are removed from the parent's children array and the parent's summary is updated

#### Scenario: Delete spanning multiple levels
- **WHEN** a delete range spans content across children of different inner nodes at multiple tree levels
- **THEN** the content is correctly removed, all summaries are updated, and the tree remains balanced

### Requirement: COW path-copying on delete
When a `TextRope` value is copied (via Swift's value semantics) and one copy is mutated via `delete`, the mutation SHALL NOT affect the other copy. The implementation MUST use copy-on-write path-copying: only nodes along the mutation path from root to the affected leaves are copied. Shared subtrees not on the mutation path MUST remain shared (reference-identical).

#### Scenario: Delete on shared rope preserves original
- **WHEN** `var a = TextRope("hello world")`, `var b = a`, then `b.delete(in: NSRange(location: 5, length: 6))`
- **THEN** `a.content` is `"hello world"` and `b.content` is `"hello"`

#### Scenario: Path-copying shares unaffected subtrees
- **WHEN** a multi-leaf rope is copied and one copy is mutated via delete
- **THEN** nodes not on the root-to-affected-leaf mutation path remain reference-identical between the two copies

#### Scenario: Single-owner mutation avoids copying
- **WHEN** a `TextRope` has a single owner (no copies exist) and `delete` is called
- **THEN** the mutation modifies nodes in place without allocating new node objects along the path

### Requirement: Undersized leaf merging after delete
When a deletion causes a leaf's chunk to fall below `Node.minChunkUTF8` bytes, the leaf MUST be merged with an adjacent sibling or have content redistributed. If the undersized leaf and an adjacent sibling have a combined UTF-8 size ≤ `Node.maxChunkUTF8`, they SHALL be merged into a single leaf. If merging would exceed `maxChunkUTF8`, content SHALL be redistributed between the two nodes so both are above `minChunkUTF8`. Redistribution MUST respect UTF-8 character boundaries and the `\r\n` split invariant.

#### Scenario: Leaf becomes undersized and merges with sibling
- **WHEN** a deletion reduces a leaf's chunk below `minChunkUTF8` bytes and the combined size with an adjacent sibling is ≤ `maxChunkUTF8`
- **THEN** the two leaves are merged into one leaf containing the concatenated content, the parent's child count decreases by one, and the merged leaf's summary is correct

#### Scenario: Leaf becomes undersized and redistributes with sibling
- **WHEN** a deletion reduces a leaf's chunk below `minChunkUTF8` bytes but merging with the adjacent sibling would exceed `maxChunkUTF8`
- **THEN** content is redistributed between the two leaves so both are above `minChunkUTF8`, both chunks contain valid UTF-8, and the `\r\n` split invariant is preserved

#### Scenario: Deletion within a leaf that stays above minimum size
- **WHEN** a deletion reduces a leaf's chunk but it remains at or above `minChunkUTF8`
- **THEN** no merging or redistribution occurs — only the leaf's summary is updated

#### Scenario: Complete removal of a leaf
- **WHEN** a deletion removes all content from a leaf (its entire range is within the delete range)
- **THEN** the leaf is removed from the parent's children array and the parent handles the reduced child count

### Requirement: Merge propagation through inner nodes
When merging leaves reduces an inner node's child count below `Node.minChildren`, the inner node MUST be merged with an adjacent sibling or have children redistributed. This merge propagation SHALL continue upward as needed. If the root inner node is reduced to a single child, the single child SHALL become the new root, decreasing tree height by one. Root collapse SHALL repeat until the root is a leaf or has ≥ 2 children.

#### Scenario: Inner node falls below minimum children and merges
- **WHEN** leaf merges reduce an inner node's child count below `minChildren` and the combined child count with an adjacent sibling is ≤ `maxChildren`
- **THEN** the two inner nodes merge into one, and the merge propagates to the grandparent

#### Scenario: Inner node falls below minimum children and redistributes
- **WHEN** leaf merges reduce an inner node's child count below `minChildren` but merging with a sibling would exceed `maxChildren`
- **THEN** children are redistributed between the two inner nodes so both are above `minChildren`

#### Scenario: Root collapses when reduced to single child
- **WHEN** merging reduces the root inner node to a single child
- **THEN** the single child becomes the new root, the tree height decreases by one, and all summaries remain correct

#### Scenario: Cascading merges through multiple levels
- **WHEN** a single delete triggers merges at multiple levels of the tree
- **THEN** each level correctly merges or redistributes, the tree height adjusts as needed, and the final tree satisfies B-tree balance invariants

### Requirement: Always-rooted invariant on delete-all
When the entire content of the rope is deleted, the result MUST be an empty leaf root — not nil, not an inner node with no children. The rope's `isEmpty` property SHALL return `true`. The rope's `utf16Count`, `utf8Count` SHALL be `0`. The rope's `content` SHALL be an empty string.

#### Scenario: Delete all content from a single-leaf rope
- **WHEN** a rope contains `"hello"` and `delete(in: NSRange(location: 0, length: 5))` is called
- **THEN** `content` is `""`, `isEmpty` is `true`, `utf16Count` is `0`, and the root is a leaf node

#### Scenario: Delete all content from a multi-level rope
- **WHEN** a multi-level rope with many leaves has its entire content deleted via `delete(in: NSRange(location: 0, length: utf16Count))`
- **THEN** `content` is `""`, `isEmpty` is `true`, and the root is an empty leaf node (not an inner node, not nil)

#### Scenario: Rope is usable after delete-all
- **WHEN** all content is deleted from a rope and then new content is inserted
- **THEN** the rope functions correctly — `insert("new", at: 0)` results in `content` being `"new"`

### Requirement: Summary correctness after delete
After any call to `delete(in:)`, every node in the tree MUST have a correct summary. For leaf nodes, the summary MUST equal `Summary.of(chunk)`. For inner nodes, the summary MUST equal the sum of all children's summaries. The root summary MUST reflect the total UTF-8 byte count, UTF-16 code unit count, and newline count of the entire rope content.

#### Scenario: Summary after simple delete
- **WHEN** a rope contains `"hello\nworld"` and `delete(in: NSRange(location: 5, length: 6))` is called
- **THEN** `root.summary.utf8` is `5`, `root.summary.utf16` is `5`, and `root.summary.lines` is `0`

#### Scenario: Summary after delete with multi-byte characters
- **WHEN** a rope contains `"🎉hello"` (utf8: 9, utf16: 7) and `delete(in: NSRange(location: 0, length: 2))` is called (removes the emoji)
- **THEN** `root.summary.utf8` is `5`, `root.summary.utf16` is `5`, and `root.summary.lines` is `0`

#### Scenario: Summary consistency across tree after merge
- **WHEN** a deletion triggers leaf merges and inner node merges
- **THEN** a full tree traversal confirms that every inner node's summary equals the sum of its children's summaries, and the root summary matches a fresh `Summary.of(rope.content)`

#### Scenario: Summary after delete preserving newlines
- **WHEN** a rope contains `"line1\nline2\nline3"` and `delete(in: NSRange(location: 5, length: 6))` is called (removes `"\nline2"`)
- **THEN** `root.summary.lines` is `1` (one remaining `\n` between "line1" and "\nline3" — content is `"line1\nline3"`)
