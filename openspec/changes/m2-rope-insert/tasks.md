## 1. Leaf Splitting Infrastructure

- [ ] 1.1 Write tests for `Node` leaf splitting: split at midpoint, split respects UTF-8 character boundaries, split respects `\r\n` invariant, split of chunk with only multi-byte characters, split point adjustment when midpoint lands inside multi-byte sequence
- [ ] 1.2 Implement `Node.splitLeaf() -> Node` in `Sources/TextRope/Node+Split.swift` — find UTF-8 midpoint, adjust to character boundary, apply `\r\n` invariant, split chunk into two, recompute summaries for both halves, return the new right sibling
- [ ] 1.3 Write tests for oversized chunk producing multiple splits (inserted string > `maxChunkUTF8`), verify all resulting leaves are within size bounds and summaries are correct

## 2. Inner Node Split

- [ ] 2.1 Write tests for inner node split when children exceed `maxChildren`: correct child distribution, summary recomputation for both halves
- [ ] 2.2 Implement `Node.splitInner() -> Node` in `Sources/TextRope/Node+Split.swift` — split children array at midpoint, create new inner node with the right half, recompute summaries for both nodes, return the new right sibling

## 3. Recursive Insert with COW Path-Copying

- [ ] 3.1 Write tests for basic insert operations: insert into empty rope, insert at start/middle/end, insert empty string (no-op), insert with multi-byte characters and emoji
- [ ] 3.2 Implement the recursive insert descent in `Sources/TextRope/TextRope+Insert.swift` — `ensureUnique()` at root, navigate to correct child using UTF-16 summary accumulation, `ensureUniqueChild(at:)` at each level, splice string into leaf chunk at the translated `String.Index`
- [ ] 3.3 Implement split handling in the insert return path — if leaf returns a split sibling, insert it into the parent's children array; if parent overflows, split the parent; if root splits, create new root

## 4. Summary Correctness

- [ ] 4.1 Write tests verifying summary correctness: after simple insert (utf8, utf16, lines), after insert with emoji (utf8 ≠ utf16), after insert containing newlines, after multi-level cascading splits — validate every node's summary via full tree traversal
- [ ] 4.2 Implement bottom-up summary updates on the insert unwind path — recompute leaf summary from chunk after splice, recompute inner node summary from children after child insert/split

## 5. COW Independence

- [ ] 5.1 Write tests for COW: copy rope then insert on copy — original unchanged; insert on single-owner rope mutates in place; verify unaffected subtrees remain reference-identical after path-copying insert on a shared rope

## 6. Edge Cases and Integration

- [ ] 6.1 Write tests for insert at UTF-16 offset that falls between surrogate pair halves (offset points to low surrogate of an emoji) — verify correct placement
- [ ] 6.2 Write tests for `\r\n` preservation across insert: insert between `\r` and `\n`, insert text containing `\r\n` that triggers a split at the `\r\n` boundary
- [ ] 6.3 Write test for repeated insertions that grow the tree from a single leaf to 3+ levels, verify final `content` matches expected string and root summary matches `Summary.of(content)`
