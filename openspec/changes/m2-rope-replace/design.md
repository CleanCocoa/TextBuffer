## Context

TextRope's insert (TASK-015) and delete (TASK-016) operations are complete. Replace is the final core mutation, specified in SPEC.md §4.3 as `mutating func replace(range utf16Range: NSRange, with string: String)`. TASK-017 explicitly states: "Start with delete + insert composition. Optimize later if benchmarks warrant." This is a deliberately thin operation that composes existing primitives.

Key architectural decisions are already settled: ADR-004 (UTF-8 storage with cached UTF-16 counts), ADR-006 (always-rooted rope), ADR-007 (no parent pointers). The COW path-copying discipline and summary propagation patterns are established by insert and delete.

## Goals / Non-Goals

**Goals:**
- Implement `replace(range:with:)` as specified in SPEC.md §4.3
- Compose as `delete(in:)` followed by `insert(_:at:)` — two separate tree traversals
- Handle degenerate cases correctly: empty string → pure delete, empty range → pure insert, both empty → no-op
- Ensure summary correctness after the composed operation

**Non-Goals:**
- Single-pass fused replace optimization (explicitly deferred per TASK-017: "optimize later if benchmarks warrant")
- Merge or rebalance improvements beyond what delete and insert already provide
- RopeBuffer integration (TASK-019)
- Comprehensive edge-case testing beyond replace-specific scenarios (TASK-018)

## Decisions

### 1. Compose as delete then insert (no fusion)

TASK-017 explicitly prescribes starting with delete + insert composition. The implementation is:

```swift
public mutating func replace(range utf16Range: NSRange, with string: String) {
    if utf16Range.length > 0 {
        delete(in: utf16Range)
    }
    if !string.isEmpty {
        insert(string, at: utf16Range.location)
    }
}
```

The delete collapses the range, then insert splices the new text at the range's start location. Both operations independently maintain COW invariants, tree balance, and summary correctness.

**Why not fuse?** A single-pass replace that simultaneously removes and inserts would be more efficient (one tree traversal instead of two), but adds significant complexity. The two-pass approach is correct by construction since both operations are already tested. Per TASK-017, fusion is deferred until benchmarks show it's needed.

**Alternative considered:** Direct leaf-level splice (remove old text, insert new text in one chunk operation). This would skip intermediate tree states but couples replace to internal node structure. The composition approach keeps replace decoupled from tree internals.

### 2. Degenerate case short-circuiting

When the replacement string is empty, replace degenerates to delete. When the range is empty, it degenerates to insert. When both are empty, it's a no-op. The implementation guards both branches so no unnecessary tree traversal occurs in degenerate cases.

### 3. UTF-16 offset arithmetic after delete

After `delete(in: NSRange(location: L, length: K))`, the content that was at offset `L + K` is now at offset `L`. The insert offset is always `utf16Range.location` — the start of the deleted range — which is correct regardless of what was deleted.

## Risks / Trade-offs

- **Two tree traversals instead of one.** Replace performs O(log n) delete + O(log n) insert = O(log n) total, but with a constant factor of ~2×. → Mitigation: acceptable for initial implementation. TASK-017 explicitly defers optimization. The overhead is measurable only for very large ropes with frequent replaces.

- **Intermediate tree state between delete and insert.** After delete, the tree may have undersized leaves that get merged. Then insert may re-split some of those leaves. This is wasted work compared to a fused operation. → Mitigation: correctness is preserved, and the wasted work is bounded by O(log n) node operations. Profile before optimizing.

- **COW double-copy on shared ropes.** If the rope is shared, `delete` will COW-copy the path, then `insert` will operate on the already-unique nodes (no second copy needed since the first `ensureUnique()` makes the root unique for both operations). → No mitigation needed; the second operation benefits from the first's COW copy.
