# rope-delete Specification

## Purpose
Guarantees correct deletion of any UTF-16 range from a `TextRope`: content is removed across leaves, whole subtrees, and multiple levels with exact summaries afterwards; undersized leaves and inner nodes merge or redistribute under the window-clamped grapheme-first split rules, split `\r\n` pairs are rejoined, and provably starved shapes are accepted as fixed points rather than retried; deleting everything collapses the tree back to an empty leaf root; and copy-on-write path-copying keeps shared copies independent while a single-owner delete mutates the tree in place without a spurious path copy.
## Requirements
### Requirement: Delete a UTF-16 range

The `TextRope` type SHALL provide a `mutating func delete(in utf16Range: Range<Int>)` method that removes the content within the specified half-open UTF-16 code unit range. The range MUST be valid: `utf16Range.lowerBound >= 0`, `utf16Range.upperBound <= utf16Count`. After deletion, the rope's `utf16Count` SHALL equal the previous `utf16Count` minus the deleted range's `count`. The rope's `content` SHALL equal the original content with the specified range removed.

Bounds validation MUST precede the empty-range early return: an empty range at an out-of-bounds location MUST cause a precondition failure even though nothing would be deleted. An empty range at an in-bounds location (`0 <= k <= utf16Count` for `k..<k`) SHALL be a no-op.

#### Scenario: Delete from a single-leaf rope
- **WHEN** a rope contains `"hello world"` and `delete(in: 5..<11)` is called
- **THEN** `content` is `"hello"` and `utf16Count` is `5`

#### Scenario: Delete at the beginning
- **WHEN** a rope contains `"hello world"` and `delete(in: 0..<6)` is called
- **THEN** `content` is `"world"`

#### Scenario: Delete at the end
- **WHEN** a rope contains `"hello world"` and `delete(in: 5..<11)` is called
- **THEN** `content` is `"hello"`

#### Scenario: Delete in the middle
- **WHEN** a rope contains `"hello world"` and `delete(in: 2..<8)` is called
- **THEN** `content` is `"herld"`

#### Scenario: Delete empty range is a no-op
- **WHEN** `delete(in: k..<k)` is called with an in-bounds `k` (`0 <= k <= utf16Count`) — e.g. `delete(in: 3..<3)` on a rope containing `"hello"`
- **THEN** `content` remains `"hello"` and the tree structure is unchanged

#### Scenario: Delete with multi-byte characters
- **WHEN** a rope contains `"café🎉"` (UTF-16 length 6) and `delete(in: 4..<6)` is called
- **THEN** `content` is `"café"` and `utf16Count` is `4` (emoji was 2 UTF-16 code units)

#### Scenario: Delete spanning a surrogate pair boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16: `a`, high surrogate, low surrogate, `b` — length 4) and `delete(in: 1..<3)` is called
- **THEN** `content` is `"ab"` — the entire emoji is removed

#### Scenario: Out-of-bounds range traps
- **WHEN** `delete(in:)` is called with `lowerBound < 0` or `upperBound > utf16Count`
- **THEN** a precondition failure MUST occur, whether the range is empty or not

#### Scenario: Empty out-of-bounds range traps
- **WHEN** `delete(in: k..<k)` is called with `k > utf16Count` or `k < 0` — e.g. `delete(in: 500..<500)` on a rope containing `"hello"`
- **THEN** a precondition failure MUST occur
- **AND** the call SHALL NOT silently succeed as a no-op

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

When the rope has a single owner, the delete descent MUST NOT hold a strong reference to a child node across the `ensureUniqueChild(at:)` call for that child's index. Reading a child's metrics for the descent decision (for example `children[i].summary.utf16`) MUST NOT bind the child node itself to a local that outlives the uniqueness check, because such an alias makes `isKnownUniquelyReferenced` observe a shared node and forces an unnecessary path copy on every delete. With no such alias present, a single-owner delete that leaves every affected node within its size bounds SHALL leave the entire root-to-leaf path reference-identical.

Deletes that push a leaf below `Node.minChunkUTF8` or an inner node below `Node.minChildren` trigger merging or redistribution, which constructs replacement nodes by design. The reference-identity guarantee above SHALL NOT be read as forbidding those allocations.

#### Scenario: Delete on shared rope preserves original

- **WHEN** `var a = TextRope("hello world")`, `var b = a`, then `b.delete(in: 5..<11)`
- **THEN** `a.content` is `"hello world"` and `b.content` is `"hello"`

#### Scenario: Path-copying shares unaffected subtrees

- **WHEN** a multi-leaf rope is copied and one copy is mutated via delete
- **THEN** nodes not on the root-to-affected-leaf mutation path remain reference-identical between the two copies

#### Scenario: Single-owner mutation avoids copying

- **WHEN** a `TextRope` has a single owner (no copies exist), the tree has more than one level, and `delete` removes a range that lies wholly inside one leaf and leaves every affected node within its size bounds
- **THEN** the root, every inner node on the path from the root to that leaf, and the leaf itself SHALL each remain reference-identical (`===`) to the node held at the same position before the delete
- **AND** the rope's `content` SHALL equal the original content with the deleted range removed

#### Scenario: Single-owner delete leaves off-path siblings identical

- **WHEN** a single-owner multi-level rope is deleted as above
- **THEN** every node not on the root-to-leaf mutation path SHALL also remain reference-identical, so that no part of the tree is reallocated

#### Scenario: Single-owner in-place guarantee is pinned by test

- **WHEN** the delete descent is changed so that a child node is bound to a local that is still live when `ensureUniqueChild(at:)` runs for that index
- **THEN** at least one named test SHALL fail — the guarantee MUST NOT be verifiable only by inspecting the root or a node that lies off the delete path

#### Scenario: Rebalancing delete may allocate replacement nodes

- **WHEN** a single-owner delete reduces a leaf below `Node.minChunkUTF8` or an inner node below `Node.minChildren`, so that merging or redistribution runs
- **THEN** the operation MAY replace the affected leaves or inner nodes with newly constructed nodes, and the resulting tree SHALL still satisfy the content, summary, and structural invariants for delete

### Requirement: Undersized leaf merging after delete
When a deletion causes a leaf's chunk to fall below `Node.minChunkUTF8` bytes, or leaves a `\r` at the end of one leaf and a `\n` at the start of the next, the affected leaves MUST be merged or have their content redistributed. Because every conforming leaf holds at most `maxChunkUTF8` bytes, the combined slice is at most `2 * maxChunkUTF8` (4096) bytes. The outcome SHALL be determined by the combined size `count` and by the legal window `[low, high]`, where `low = max(minChunkUTF8, count - maxChunkUTF8)` and `high = min(maxChunkUTF8, count - minChunkUTF8)`:

- `count <= maxChunkUTF8` → the two leaves SHALL be merged into a **single** leaf.
- the window holds a `Character` boundary → the content SHALL be redistributed into **two** leaves, split at the boundary nearest `(count + 1) / 2` within the window, ties resolving to the lower offset. Both leaves SHALL be within `[minChunkUTF8, maxChunkUTF8]`.
- the window holds no `Character` boundary and `count >= 3 * minChunkUTF8` → the content SHALL be redistributed into **three** leaves by balanced redistribution (targets at `count / 3` and `2 * count / 3`, each moved to the nearest `Character` boundary with minimal deviation), each within `[minChunkUTF8, maxChunkUTF8]`.
- otherwise (`maxChunkUTF8 < count < 3 * minChunkUTF8` with an empty window) → boundary starvation: no shape satisfies both bounds. The content SHALL be split at the `Character` boundary within `[count - maxChunkUTF8, min(maxChunkUTF8, count - 1)]` that minimizes the total shortfall below `minChunkUTF8`, ties resolving to the lower offset. No leaf SHALL exceed `maxChunkUTF8`; the resulting undersized leaf is permitted under the grapheme-first chunk-size bounds.

Every split point MUST fall on a `Character` boundary — never inside a grapheme cluster, not even at a Unicode scalar boundary — which preserves the `\r\n` invariant unconditionally. Redistribution MUST NOT search outside the ranges named above; in particular it MUST NOT fall back to an unbounded backward walk from the midpoint.

Merges do not retry: a leaf that is out of bounds under proven boundary starvation is a fixed point. Subsequent merge scans MUST accept it without re-attempting redistribution, so repeated operations over the same shape neither oscillate nor re-run the failed split.

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

#### Scenario: Starved band takes the minimal-deviation split
- **WHEN** redistribution runs on a 2049-byte combined slice whose window `[1024, 1025]` is spanned by a single 4-byte scalar
- **THEN** the result SHALL be two leaves of 1023 and 1026 bytes — the shortfall-minimizing split among the available `Character` boundaries

#### Scenario: Starved leaf is accepted without a merge retry
- **WHEN** subsequent operations traverse a leaf that is undersized under proven boundary starvation (e.g. the 1023-byte leaf of the previous scenario)
- **THEN** the merge scan SHALL accept the leaf as-is — re-running the same merge on the same pair SHALL reproduce the identical shape, with no repeated redistribution attempt

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
- **WHEN** a rope contains `"hello"` and `delete(in: 0..<5)` is called
- **THEN** `content` is `""`, `isEmpty` is `true`, `utf16Count` is `0`, and the root is a leaf node

#### Scenario: Delete all content from a multi-level rope
- **WHEN** a multi-level rope with many leaves has its entire content deleted via `delete(in: 0..<utf16Count)`
- **THEN** `content` is `""`, `isEmpty` is `true`, and the root is an empty leaf node (not an inner node, not nil)

#### Scenario: Rope is usable after delete-all
- **WHEN** all content is deleted from a rope and then new content is inserted
- **THEN** the rope functions correctly — `insert("new", at: 0)` results in `content` being `"new"`

### Requirement: Summary correctness after delete

After any call to `delete(in:)`, every node in the tree MUST have a correct summary. For leaf nodes, the summary MUST equal `Summary.of(chunk)`. For inner nodes, the summary MUST equal the sum of all children's summaries. The root summary MUST reflect the total UTF-8 byte count, UTF-16 code unit count, and newline count of the entire rope content.

#### Scenario: Summary after simple delete
- **WHEN** a rope contains `"hello\nworld"` and `delete(in: 5..<11)` is called
- **THEN** `root.summary.utf8` is `5`, `root.summary.utf16` is `5`, and `root.summary.lines` is `0`

#### Scenario: Summary after delete with multi-byte characters
- **WHEN** a rope contains `"🎉hello"` (utf8: 9, utf16: 7) and `delete(in: 0..<2)` is called (removes the emoji)
- **THEN** `root.summary.utf8` is `5`, `root.summary.utf16` is `5`, and `root.summary.lines` is `0`

#### Scenario: Summary consistency across tree after merge
- **WHEN** a deletion triggers leaf merges and inner node merges
- **THEN** a full tree traversal confirms that every inner node's summary equals the sum of its children's summaries, and the root summary matches a fresh `Summary.of(rope.content)`

#### Scenario: Summary after delete preserving newlines
- **WHEN** a rope contains `"line1\nline2\nline3"` and `delete(in: 5..<11)` is called (removes `"\nline2"`)
- **THEN** `root.summary.lines` is `1` (one remaining `\n` between "line1" and "\nline3" — content is `"line1\nline3"`)

