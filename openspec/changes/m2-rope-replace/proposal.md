## Why

TextRope has insert (TASK-015) and delete (TASK-016) operations. TASK-017 completes the mutation triad with `replace(range:with:)`, the final core operation required before the comprehensive test suite (TASK-018) and RopeBuffer integration (TASK-019). Replace is composed as delete + insert, keeping the implementation simple and leveraging already-proven mutation paths.

## What Changes

- Implement `public mutating func replace(range utf16Range: NSRange, with string: String)` on `TextRope`
- Compose replace as `delete(in:)` followed by `insert(_:at:)`, reusing existing mutation infrastructure
- Handle degenerate cases: empty replacement string = pure delete, empty range = pure insert
- Ensure summaries are correct after the composed operation

Corresponds to **TASK-017** in the master roadmap (Milestone 2).

## Capabilities

### New Capabilities
- `rope-replace`: Replace a UTF-16 range with new text, composed as delete + insert, with correct summary propagation. Empty replacement = delete. Empty range = insert.

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **New files:** `Sources/TextRope/TextRope+Replace.swift`, `Tests/TextRopeTests/TextRopeReplaceTests.swift`
- **Dependencies:** Requires TASK-015 (insert) and TASK-016 (delete) to be complete
- **API surface:** Adds one public mutating method to `TextRope`
- **Unlocks:** TASK-018 (comprehensive test suite), TASK-019 (RopeBuffer integration)
