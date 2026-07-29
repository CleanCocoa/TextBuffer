## Why

TextRope needs its first mutating operation. TASK-015 implements `insert(_:at:)`, the foundation that TASK-016 (delete) and TASK-017 (replace) build on. Insert exercises the full COW path-copying discipline, leaf splitting with the `\r\n` split invariant, split propagation through inner nodes, and bottom-up summary updates — establishing the mutation patterns for all subsequent rope operations.

## What Changes

- Implement `public mutating func insert(_ string: String, at utf16Offset: Int)` on `TextRope`
- Implement leaf splitting on `Node` when a chunk exceeds `maxChunkUTF8` after insertion, respecting the split invariant (never split between `\r` and `\n`)
- Implement split propagation: when a leaf splits, the parent inner node gains a child; if the parent overflows `maxChildren`, it splits too, potentially up to the root
- COW path-copying on every mutation: `ensureUnique()` at the root, `ensureUniqueChild(at:)` at each level along the path
- Bottom-up summary recomputation after structural changes

Corresponds to **TASK-015** in the master roadmap (Milestone 2).

## Capabilities

### New Capabilities
- `rope-insert`: Insert text at a UTF-16 offset with COW path-copying, leaf splitting at valid UTF-8 boundaries respecting the `\r\n` invariant, split propagation through inner nodes, and summary updates

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **New files:** `Sources/TextRope/TextRope+Insert.swift`, `Sources/TextRope/Node+Split.swift`, `Tests/TextRopeTests/TextRopeInsertTests.swift`
- **Dependencies:** Requires TASK-012 (COW infrastructure) and TASK-014 (UTF-16 navigation) to be complete
- **API surface:** Adds one public mutating method to `TextRope`
- **Unlocks:** TASK-016 (delete), TASK-017 (replace) — all subsequent mutation operations depend on the patterns established here
