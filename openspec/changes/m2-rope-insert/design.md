## Context

TextRope has its structural foundation in place: `Node` and `Summary` types (TASK-011), COW infrastructure (TASK-012), leaf construction and content materialization (TASK-013), and UTF-16 offset navigation (TASK-014). The rope can be built and read but not mutated. Insert is the first mutation operation and establishes the patterns that delete and replace will follow.

The technical blueprint for insert is defined in SPEC.md §4.3. Key architectural decisions are settled in ADR-004 (UTF-8 storage with cached UTF-16 counts), ADR-005 (ContiguousArray children), ADR-006 (always-rooted rope), and ADR-007 (no parent pointers — mutations return status up the call stack).

## Goals / Non-Goals

**Goals:**
- Implement `insert(_:at:)` as specified in SPEC.md §4.3
- Establish the recursive mutation pattern: descend with COW path-copying, mutate at the leaf, return split status up the call stack
- Implement leaf splitting with the `\r\n` split invariant
- Implement inner node splitting when children overflow `maxChildren`
- Ensure summary correctness after all structural changes

**Non-Goals:**
- Delete, replace, or merge operations (TASK-016, TASK-017)
- Rebalancing beyond what split propagation requires (TASK-018)
- Cursor/iterator types for sequential access
- RopeBuffer integration (TASK-019)
- Performance benchmarking or ManagedBuffer optimization (ADR-005 upgrade path)

## Decisions

### 1. Recursive insert returning split result

Per ADR-007, there are no parent pointers. The insert function descends recursively through the tree. At the leaf, it inserts the string and potentially splits. The return type communicates whether a split occurred:

- **No split:** The caller updates its child's summary in place.
- **Split:** The caller receives a new sibling node to insert into its children array. If the caller's children then exceed `maxChildren`, the caller itself splits.
- **Root split:** If the root node splits, `TextRope` creates a new root with the two halves as children.

This is standard B-tree insertion style. The alternative (iterative with an explicit stack) is equivalent but less idiomatic in Swift.

### 2. Leaf insertion and splitting

When inserting into a leaf:
1. Navigate to the UTF-16 offset within the chunk (using the leaf-level UTF-16 → String.Index translation from TASK-014)
2. Splice the string into the chunk at that position
3. If the resulting chunk exceeds `maxChunkUTF8`, split it

**Split point selection:** Find the midpoint in UTF-8 bytes, then adjust:
- Walk to the nearest UTF-8 character boundary (don't split in the middle of a multi-byte sequence)
- Apply the `\r\n` invariant: if the byte before the split is `\r` and the byte after is `\n`, shift the split point by one byte (include the `\n` in the left chunk, or shift right — either direction works as long as the pair stays together)

The inserted string itself may be large enough to require multiple splits. In that case, the leaf produces multiple new nodes. The simplest approach: after splicing, if oversized, split once at the midpoint, then recursively check each half. This naturally handles arbitrarily large insertions.

### 3. Inner node split on child overflow

When a child split adds a new child to an inner node that already has `maxChildren` children:
1. Insert the new child at the correct position
2. If `children.count > maxChildren`, split the inner node at `children.count / 2`
3. Return the new sibling to the caller

Summary for each half is recomputed by summing child summaries.

### 4. COW path-copying discipline

The mutation path from root to leaf must be COW-copied in a single top-down pass (SPEC.md §4.3):
1. `TextRope.ensureUnique()` — copy root if shared
2. At each inner level: `ensureUniqueChild(at: childIndex)` before descending
3. Mutate the (now-unique) leaf in place
4. Return split status up — parent inserts new child into its (already-unique) children array

No second traversal pass. The COW copy and the mutation happen in the same descent.

### 5. Summary update strategy

Summaries are updated bottom-up as the recursion unwinds:
- After leaf mutation: recompute the leaf's summary from its chunk
- After handling a child's split result: recompute the parent's summary from its children
- Use `Summary.of(_:)` for leaves, sum of `child.summary` for inner nodes

This is O(depth) work per insert — one summary recomputation per level.

## Risks / Trade-offs

- **Large insertions create multiple splits.** Inserting a 100KB string into a single leaf could cascade into many splits. This is correct behavior (the tree grows to accommodate the content), but should be tested to ensure summary correctness after cascading splits. → Mitigation: test with insertions that trigger 2+ levels of splitting.

- **Split point edge cases with multi-byte characters.** A naive midpoint split could land inside a multi-byte UTF-8 sequence (2-4 bytes). → Mitigation: always adjust to a character boundary. Swift's `String.Index` round-down behavior helps — use `String.Index` rounding to ensure valid boundaries.

- **\r\n at chunk boundaries.** If a `\r` ends up as the last byte of one chunk and `\n` as the first byte of the next, line counting becomes incorrect (the pair is one newline but would be counted as two). → Mitigation: the split invariant prevents this by construction. Test explicitly with `\r\n` at the split point.

- **Empty chunk after split.** If the split point is at position 0 or at the end, one side is empty. → Mitigation: with midpoint splitting this shouldn't occur for oversized chunks, but validate that min/max chunk size constraints prevent degenerate cases.
