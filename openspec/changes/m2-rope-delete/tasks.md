## 1. Undersized Leaf Merging Infrastructure

- [ ] 1.1 Write tests for `Node` leaf merging: merge two undersized leaves into one when combined size ≤ `maxChunkUTF8`, verify merged chunk content and summary correctness
- [ ] 1.2 Write tests for `Node` leaf redistribution: when combined size > `maxChunkUTF8`, redistribute content between two leaves so both are above `minChunkUTF8`, verify `\r\n` split invariant and UTF-8 character boundaries are respected
- [ ] 1.3 Implement `Node` leaf merge and redistribute logic in `Sources/TextRope/Node+Merge.swift` — concatenate chunks or find a valid split point, recompute summaries for resulting leaves

## 2. Inner Node Merge and Root Collapse

- [ ] 2.1 Write tests for inner node merge when child count falls below `minChildren`: correct child distribution after merge, summary recomputation
- [ ] 2.2 Write tests for inner node redistribution when merging would exceed `maxChildren`: children are moved from the fuller sibling so both are above `minChildren`
- [ ] 2.3 Write tests for root collapse: root with single child collapses to that child as new root, repeated collapse until root is a leaf or has ≥ 2 children
- [ ] 2.4 Implement inner node merge, redistribution, and root collapse logic in `Sources/TextRope/Node+Merge.swift`

## 3. Recursive Delete with COW Path-Copying

- [ ] 3.1 Write tests for basic delete operations: delete from single-leaf rope (beginning, middle, end), delete empty range (no-op), delete with multi-byte characters and emoji, delete spanning a surrogate pair
- [ ] 3.2 Write tests for spanning deletes: delete across two leaves, delete removing entire intermediate leaves, delete spanning multiple levels of the tree
- [ ] 3.3 Implement the recursive delete descent in `Sources/TextRope/TextRope+Delete.swift` — `ensureUnique()` at root, navigate to affected children using UTF-16 summary accumulation, `ensureUniqueChild(at:)` at each level, remove content from edge leaves, remove intermediate children entirely
- [ ] 3.4 Implement merge handling in the delete return path — if a child becomes undersized, merge or redistribute with sibling; if an inner node becomes undersized, propagate upward; if root collapses, reduce tree height

## 4. Always-Rooted Invariant

- [ ] 4.1 Write tests for delete-all: delete entire content from a single-leaf rope, from a two-leaf rope, from a multi-level rope — verify result is an empty leaf root with `isEmpty == true`, `utf16Count == 0`, `utf8Count == 0`
- [ ] 4.2 Write test for usability after delete-all: delete everything then insert new content, verify rope functions correctly

## 5. Summary Correctness

- [ ] 5.1 Write tests verifying summary correctness: after simple delete (utf8, utf16, lines), after delete removing multi-byte characters, after delete removing newlines, after multi-level cascading merges — validate every node's summary via full tree traversal
- [ ] 5.2 Implement bottom-up summary updates on the delete unwind path — recompute leaf summary from chunk after removal, recompute inner node summary from children after child removal/merge

## 6. COW Independence

- [ ] 6.1 Write tests for COW: copy rope then delete on copy — original unchanged; delete on single-owner rope mutates in place; verify unaffected subtrees remain reference-identical after path-copying delete on a shared rope

## 7. Edge Cases and Integration

- [ ] 7.1 Write tests for delete with `\r\n` sequences: delete that leaves `\r` at end of one leaf and `\n` at start of next — verify merge or redistribution preserves the pair together
- [ ] 7.2 Write test for repeated deletions that shrink the tree from 3+ levels down to a single leaf, verify final `content` matches expected string and root summary matches `Summary.of(content)`
- [ ] 7.3 Write test for alternating insert and delete operations to verify structural integrity is maintained across mixed mutations
