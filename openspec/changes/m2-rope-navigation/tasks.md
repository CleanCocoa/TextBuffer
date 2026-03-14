## 1. findLeaf — Tree Descent

- [ ] 1.1 Write tests for `findLeaf(utf16Offset:)` on a single-leaf rope: offset 0, mid-chunk, end-of-chunk
- [ ] 1.2 Write tests for `findLeaf(utf16Offset:)` on a multi-leaf rope: first leaf, interior leaf, last leaf, end-of-document offset
- [ ] 1.3 Write test for `findLeaf(utf16Offset:)` with offset beyond bounds (precondition failure)
- [ ] 1.4 Implement `findLeaf(utf16Offset:)` in `TextRope+Navigation.swift` — inner-node descent using cumulative `summary.utf16`, return leaf + remaining offset

## 2. Leaf-Level UTF-16 → String.Index Translation

- [ ] 2.1 Write tests for UTF-16-to-`String.Index` translation: ASCII chunk, multi-byte characters (CJK, accented Latin), surrogate pairs (emoji above U+FFFF)
- [ ] 2.2 Implement leaf-level `String.Index` resolution via `chunk.utf16` view indexing in `TextRope+Navigation.swift`

## 3. content(in:) — Range Extraction

- [ ] 3.1 Write tests for `content(in:)` with range inside a single leaf
- [ ] 3.2 Write tests for `content(in:)` with range spanning multiple leaves (head + middle + tail)
- [ ] 3.3 Write tests for `content(in:)` edge cases: empty range, full-document range, range at boundaries (offset 0, offset == utf16Count)
- [ ] 3.4 Write tests for `content(in:)` with multi-byte/emoji/surrogate-pair content
- [ ] 3.5 Write test for `content(in:)` on empty rope with `NSRange(location: 0, length: 0)`
- [ ] 3.6 Write test for `content(in:)` with range exceeding bounds (precondition failure)
- [ ] 3.7 Implement `content(in utf16Range: NSRange) -> String` in `TextRope+Navigation.swift` — locate start leaf, traverse collecting head/middle/tail, concatenate result

## 4. Read-Only Invariant

- [ ] 4.1 Write test verifying navigation does not trigger COW: copy a rope, call `content(in:)` on both, assert they still share the same root identity
