## Why

TASK-015 (insert), TASK-016 (delete), and TASK-017 (replace) all depend on the ability to navigate the rope tree to a UTF-16 offset. TASK-014 implements this foundational navigation layer — O(log n) tree descent using cached `summary.utf16` counts (per ADR-004) and leaf-level `String.Index` translation — plus `content(in utf16Range:)` for extracting substrings by UTF-16 range. Without this, no mutation operation can locate its target position.

## What Changes

- Add `findLeaf(utf16Offset:)` internal method on `TextRope` that descends the B-tree using cumulative `summary.utf16` at each inner node level, returning the target leaf node plus the remaining UTF-16 offset within that leaf.
- Add leaf-level UTF-16-to-`String.Index` translation that walks the chunk's `utf16` view to convert the remaining offset.
- Implement `public func content(in utf16Range: NSRange) -> String` on `TextRope` — locates start and end leaves via tree descent, extracts and concatenates the relevant substring slices.

## Capabilities

### New Capabilities
- `rope-utf16-navigation`: UTF-16 offset tree descent using cumulative `summary.utf16`, leaf-level `String.Index` translation, and content extraction by UTF-16 range.

### Modified Capabilities
_(none)_

## Impact

- **New file:** `Sources/TextRope/TextRope+Navigation.swift`
- **New file:** `Tests/TextRopeTests/TextRopeNavigationTests.swift`
- **API:** Adds `content(in:)` public method on `TextRope` (declared in SPEC.md §4.3)
- **Internal API:** Adds `findLeaf(utf16Offset:)` used by TASK-015/016/017
- **Dependencies:** Requires TASK-013 (construction + content) and TASK-011 (Node/Summary types)
