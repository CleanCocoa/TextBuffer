## Context

TextRope stores text as UTF-8 in a B-tree of string chunks with cached `Summary` metrics (`utf8`, `utf16`, `lines`) per node (ADR-004). All `Buffer` protocol operations use `NSRange` (UTF-16 offsets). Before any mutation (TASK-015/016/017) can proceed, the rope must be able to locate a UTF-16 offset within the tree and extract content by UTF-16 range.

TASK-013 established construction (`init(_:)`) and full-content materialization (`content`). This change adds targeted navigation — descending the tree to a specific UTF-16 offset and extracting substrings without materializing the entire rope.

## Goals / Non-Goals

**Goals:**
- O(log n) tree descent to the leaf containing a given UTF-16 offset
- Leaf-level translation from UTF-16 offset to `String.Index` via the chunk's `utf16` view
- `content(in utf16Range: NSRange) -> String` that extracts a substring spanning one or more leaves
- Return type from `findLeaf` that provides enough context for mutation operations (TASK-015+)

**Non-Goals:**
- Mutation logic (insert/delete/replace) — those are TASK-015, 016, 017
- COW path-copying during navigation — navigation is read-only
- Line-based navigation — not in scope for TASK-014
- Exposing `findLeaf` as public API — it is internal to the TextRope module

## Decisions

### 1. `findLeaf` returns a leaf-offset pair

`findLeaf(utf16Offset:)` returns the target `Node` (a leaf) and the remaining UTF-16 offset within that leaf. This is the minimal information needed by both `content(in:)` and future mutation operations.

The method is `internal` on `TextRope` and operates on `self.root`. It does not need `mutating` because navigation is a read-only traversal.

**Alternative considered:** Return a full path (stack of parent-child indices) for use by mutations. Rejected — mutations will implement their own top-down descent with COW path-copying (per SPEC.md §4.3: "single top-down descent — no read-only traversal followed by a second mutation pass"). Navigation and mutation are separate concerns.

### 2. Tree descent algorithm

At each inner node, iterate `children` and accumulate `summary.utf16` counts until the cumulative total exceeds the target offset. Subtract the accumulated total of preceding siblings from the target offset, then recurse into the matching child.

This is the standard B-tree metric navigation described in SPEC.md §4.3 and ADR-004.

### 3. Leaf-level UTF-16 → String.Index translation

Once at the leaf, use `chunk.utf16.index(chunk.utf16.startIndex, offsetBy: remainingOffset)` to get a `String.Index`. This is O(chunk_size), bounded by `maxChunkUTF8` (2048 bytes) — a constant per ADR-004.

### 4. `content(in:)` handles the three-region pattern

For a UTF-16 range spanning multiple leaves, `content(in:)` collects:
1. **Head:** suffix of the first leaf (from start offset to end of chunk)
2. **Middle:** full chunks of intermediate leaves
3. **Tail:** prefix of the last leaf (from start of chunk to end offset)

When the range falls entirely within one leaf, only a single substring extraction is needed.

Implementation uses in-order traversal with offset tracking rather than two separate `findLeaf` calls, to avoid redundant tree descents.

### 5. Boundary validation

- UTF-16 offset of 0 navigates to the first leaf with offset 0
- UTF-16 offset equal to `root.summary.utf16` is the end-of-document position (valid for cursor placement, returns empty string for zero-length range)
- Offsets beyond `root.summary.utf16` are precondition failures
- Empty range (`length == 0`) returns `""` without leaf content extraction
- `content(in:)` on an empty rope with range `NSRange(location: 0, length: 0)` returns `""`

## Risks / Trade-offs

- **[Surrogate pair boundaries]** A UTF-16 offset could theoretically land between the two code units of a surrogate pair. In practice this doesn't happen with well-formed `NSRange` values from the text system, but `findLeaf` must handle this correctly because `String.UTF16View` indexing in Swift naturally handles it (indices always align to scalar boundaries). → No special mitigation needed; Swift's `String.Index` prevents invalid splits.

- **[Performance of multi-leaf extraction]** `content(in:)` concatenates substrings via `String` appending, which involves copying. For very large ranges this is O(k) where k is the extracted length. This is inherent — you can't return a substring without materializing it. → Acceptable; the `content` property already does full O(n) concatenation.

- **[Future mutation reuse]** `findLeaf` is designed for read-only navigation. Mutations will need their own descent with COW copying. There is a risk of logic duplication in the descent algorithm. → Acceptable; the descent logic is ~10 lines and mutation descent has fundamentally different requirements (COW, split propagation). Premature unification would couple unrelated concerns.
