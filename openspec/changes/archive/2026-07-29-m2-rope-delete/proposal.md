## Why

TextRope needs its second mutating operation. TASK-016 implements `delete(in:)`, building on the mutation patterns established by TASK-015 (insert). Delete introduces the inverse structural concern: where insert splits oversized leaves and propagates splits upward, delete must merge undersized leaves and propagate merges upward. Together with insert, delete completes the foundation that TASK-017 (replace) composes. The always-rooted invariant (ADR-006) requires that deleting all content produces an empty leaf root, not nil.

## What Changes

- Implement `public mutating func delete(in utf16Range: NSRange)` on `TextRope`
- Implement undersized leaf merging on `Node` when a chunk falls below `minChunkUTF8` after deletion — merge with a sibling or redistribute content
- Implement merge propagation: when merging leaves reduces an inner node below `minChildren`, the inner node merges with its sibling or redistributes children, potentially up to the root
- COW path-copying on every mutation: `ensureUnique()` at the root, `ensureUniqueChild(at:)` at each level along the path
- Bottom-up summary recomputation after structural changes
- Enforce always-rooted invariant: deleting all content produces an empty leaf root (ADR-006)

Corresponds to **TASK-016** in the master roadmap (Milestone 2, Phase 7).

## Capabilities

### New Capabilities
- `rope-delete`: Delete a UTF-16 range with COW path-copying, undersized leaf merging, merge propagation through inner nodes, always-rooted invariant (delete-all produces empty leaf root), and summary updates

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **New files:** `Sources/TextRope/TextRope+Delete.swift`, `Sources/TextRope/Node+Merge.swift`, `Tests/TextRopeTests/TextRopeDeleteTests.swift`
- **Dependencies:** Requires TASK-012 (COW infrastructure) and TASK-014 (UTF-16 navigation) to be complete
- **API surface:** Adds one public mutating method to `TextRope`
- **Unlocks:** TASK-017 (replace) — replace composes delete + insert
