## Context

TextRope has its structural foundation and first mutation operation in place: `Node` and `Summary` types (TASK-011), COW infrastructure (TASK-012), leaf construction and content materialization (TASK-013), UTF-16 offset navigation (TASK-014), and insert with leaf splitting (TASK-015). The rope can be built, read, and grown but not shrunk. Delete is the second mutation operation, introducing the inverse structural concern: merging undersized nodes after content removal.

The technical blueprint for delete is defined in SPEC.md §4.3. Key architectural decisions are settled in ADR-004 (UTF-8 storage with cached UTF-16 counts), ADR-005 (ContiguousArray children), ADR-006 (always-rooted rope — empty leaf, not nil), and ADR-007 (no parent pointers — mutations return status up the call stack).

## Goals / Non-Goals

**Goals:**
- Implement `delete(in:)` as specified in SPEC.md §4.3
- Establish the recursive merge pattern: descend with COW path-copying, remove content at leaf level, return merge status up the call stack
- Implement undersized leaf merging when a leaf's chunk falls below `minChunkUTF8`
- Implement inner node merging when an inner node falls below `minChildren`
- Ensure the always-rooted invariant: deleting all content yields an empty leaf root (ADR-006)
- Ensure summary correctness after all structural changes

**Non-Goals:**
- Replace operation (TASK-017) — composes delete + insert but is a separate task
- Rebalancing beyond what merge propagation requires
- Cursor/iterator types for sequential access
- RopeBuffer integration (TASK-019)
- Performance benchmarking or ManagedBuffer optimization (ADR-005 upgrade path)

## Decisions

### 1. Recursive delete returning merge status

Per ADR-007, there are no parent pointers. The delete function descends recursively through the tree. At the leaf level, content is removed. The return type communicates whether the node became undersized:

- **Not undersized:** The caller updates the child's summary. No structural change.
- **Undersized:** The caller attempts to merge the undersized child with a sibling. If a sibling can absorb the content (combined size ≤ `maxChunkUTF8` for leaves, ≤ `maxChildren` for inner nodes), the two merge into one, reducing the parent's child count. If the sibling is too full to absorb, redistribute content between the two nodes so both are above minimum.
- **Root collapse:** If the root inner node is reduced to a single child after merging, the single child becomes the new root, reducing tree height. Repeat until the root is a leaf or has ≥ 2 children.

This mirrors the insert pattern (split status returned up the stack) but in the opposite direction.

### 2. Leaf-level deletion

When deleting from a leaf:
1. Navigate to the UTF-16 start and end offsets within the chunk (using the leaf-level UTF-16 → String.Index translation from TASK-014)
2. Remove the substring between start and end indices
3. If the resulting chunk is below `minChunkUTF8`, signal undersized to the caller

For a deletion that spans multiple leaves:
- The start leaf loses its suffix (from the start offset to the end of the chunk)
- Intermediate leaves are removed entirely
- The end leaf loses its prefix (from the beginning of the chunk to the end offset)
- The start leaf and end leaf may both become undersized and require merging

### 3. Spanning delete across multiple leaves

A UTF-16 range may span multiple leaves and even multiple subtrees. The approach:
1. Descend to identify the subtree that contains the entire range. If the range spans children, process each affected child:
   - Left edge child: recursively delete from the start offset to end of that subtree
   - Middle children: remove entirely
   - Right edge child: recursively delete from start of that subtree to the end offset
2. After processing, the parent's children array may have been modified (middle children removed, edge children potentially undersized). Merge or redistribute as needed.
3. Return merge status to the caller.

### 4. Undersized leaf merging strategy

When a leaf is undersized (`chunk.utf8.count < minChunkUTF8`):
1. **Try merge with a sibling:** If the undersized leaf and an adjacent sibling have a combined UTF-8 size ≤ `maxChunkUTF8`, concatenate their chunks into one leaf. Remove the now-empty sibling from the parent.
2. **Redistribute:** If merging would exceed `maxChunkUTF8`, redistribute content between the two nodes so both are above `minChunkUTF8`. Find a split point in the combined content that respects the `\r\n` split invariant and UTF-8 character boundaries.

Prefer the left sibling for merging (arbitrary but consistent choice).

### 5. Inner node merge propagation

When removing a child (or merging two children into one) reduces an inner node below `minChildren`:
1. **Try merge with a sibling inner node:** If the combined child count ≤ `maxChildren`, merge the two inner nodes into one.
2. **Redistribute:** If merging would exceed `maxChildren`, move children from the fuller sibling to balance both above `minChildren`.
3. If the root inner node ends up with a single child, collapse: the single child becomes the new root.

This propagation mirrors how split propagation works for insert, but in reverse.

### 6. Always-rooted invariant on full deletion

Per ADR-006, when the entire content is deleted:
- The result is an empty leaf root (a leaf node with an empty chunk and zero summary)
- The root is never nil
- `isEmpty` returns true (`root.summary.utf8 == 0`)

This is handled naturally: deleting all content from a leaf produces an empty leaf. If the tree collapses through merging until a single empty leaf remains, that leaf becomes the root. If the deletion removes all children from an inner node, replace it with an empty leaf.

### 7. COW path-copying discipline

Same pattern as insert (SPEC.md §4.3):
1. `TextRope.ensureUnique()` — copy root if shared
2. At each inner level: `ensureUniqueChild(at: childIndex)` before descending into or modifying a child
3. For spanning deletes that touch multiple children: ensure uniqueness of all affected children
4. Mutate the (now-unique) nodes in place
5. Return merge status up — parent handles merging in its (already-unique) children array

Single top-down descent — no read-only traversal followed by a second mutation pass.

### 8. Summary update strategy

Summaries are updated bottom-up as the recursion unwinds:
- After leaf deletion: recompute the leaf's summary from its (shortened) chunk
- After removing or merging children: recompute the parent's summary from its remaining children
- Use `Summary.of(_:)` for leaves, sum of `child.summary` for inner nodes

This is O(depth) work per delete — one summary recomputation per level.

## Risks / Trade-offs

- **Spanning delete complexity.** A delete range that spans many leaves and subtrees requires careful tracking of which children to remove vs. trim. The recursive approach handles this naturally (each level processes its affected children), but the implementation is more complex than insert. → Mitigation: thorough test coverage for spanning deletes at various tree depths.

- **Merge cascading.** A single delete could trigger merges at every level of the tree, collapsing it significantly. This is correct behavior but should be validated with stress tests. → Mitigation: test with deletions that trigger multi-level cascading merges.

- **`\r\n` invariant during redistribution.** When redistributing content between two leaves, the new split point must respect the `\r\n` invariant. → Mitigation: reuse the split-point logic from TASK-015 (Node+Split.swift) for finding valid split points.

- **Empty tree edge case.** Deleting everything from a single-leaf rope, or from a multi-level rope, must both produce the same result: an empty leaf root. → Mitigation: explicit tests for delete-all on single-leaf, two-leaf, and multi-level trees.

- **Delete of empty range.** `delete(in: NSRange(location: x, length: 0))` should be a no-op. → Mitigation: test and short-circuit early.
