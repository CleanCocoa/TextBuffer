## 1. Replace Tests — Degenerate Cases

- [ ] 1.1 Write tests for empty replacement string (replace degenerates to delete): replace with empty string removes content, replace entire content with empty string yields empty rope
- [ ] 1.2 Write tests for empty range (replace degenerates to insert): replace with zero-length range inserts at location, at start, at end
- [ ] 1.3 Write test for both empty (no-op): zero-length range + empty string leaves rope unchanged

## 2. Replace Tests — Core Behavior

- [ ] 2.1 Write tests for replace within a single leaf: same-length replacement, shorter replacement, longer replacement
- [ ] 2.2 Write tests for replace spanning multiple leaves: build a multi-leaf rope, replace a range that crosses leaf boundaries, verify content correctness
- [ ] 2.3 Write tests for replace with multi-byte characters: replace ASCII with emoji, replace emoji with ASCII, replace within text containing surrogate pairs

## 3. Replace Implementation

- [ ] 3.1 Implement `mutating func replace(range:with:)` in `Sources/TextRope/TextRope+Replace.swift` — guard degenerate cases (empty string → delete only, empty range → insert only, both empty → return), then compose as `delete(in:)` followed by `insert(_:at:)` at the range's start location

## 4. Summary and COW Verification

- [ ] 4.1 Write tests verifying summary correctness after replace: utf8, utf16, and lines counts match `Summary.of(rope.content)` after replacements involving newlines, emoji, and multi-leaf spans
- [ ] 4.2 Write tests for COW independence: copy rope then replace on copy — original unchanged; single-owner replace mutates in place
