## ADDED Requirements

### Requirement: UTF-16 offset navigation finds the correct leaf and String.Index
`TextRope` SHALL implement O(log n) navigation by UTF-16 offset. An internal `findLeaf(utf16Offset:)` function SHALL:
1. Descend the tree level-by-level, accumulating `summary.utf16` of preceding children to locate the correct child.
2. At the leaf, translate the remaining UTF-16 offset to a `String.Index` by walking the chunk's `utf16` view.

The `content(in utf16Range: NSRange) -> String` method SHALL use this navigation to extract substrings in O(log n + k) time where k is the length of the result.

#### Scenario: content(in:) within a single leaf
- **WHEN** `content(in: NSRange(location: 2, length: 3))` is called on a single-leaf rope containing `"hello"`
- **THEN** the result is `"llo"`

#### Scenario: content(in:) spanning multiple leaves
- **WHEN** the range spans a chunk boundary between two leaf nodes
- **THEN** the result is the correct substring of the concatenated content, with no characters dropped or duplicated at the boundary

#### Scenario: content(in:) for a range containing multi-byte characters
- **WHEN** the rope contains emoji (4-byte UTF-8, 2 UTF-16 code units each) and `content(in:)` addresses a range using UTF-16 offsets
- **THEN** the result contains only complete Unicode scalars (no partial surrogates)

#### Scenario: content(in:) for empty range
- **WHEN** `content(in: NSRange(location: 4, length: 0))` is called
- **THEN** the result is `""`

#### Scenario: content(in:) for full range
- **WHEN** `content(in: NSRange(location: 0, length: rope.utf16Count))` is called
- **THEN** the result equals `rope.content`

#### Scenario: Navigation complexity is O(log n)
- **WHEN** navigation is performed on a rope with n UTF-16 code units
- **THEN** the number of nodes visited is proportional to `log(n)` (tree height), not n

---

### Requirement: insert(_:at:) inserts a string at a UTF-16 offset with correct summary propagation
`TextRope.mutating func insert(_ string: String, at utf16Offset: Int)` SHALL:
1. Call `ensureUnique()` on the rope (COW: copy root if shared).
2. Navigate to the correct leaf using the UTF-16 offset.
3. COW-copy every node along the path before descending.
4. Insert the string into the leaf chunk at the correct byte position.
5. Split the leaf if its UTF-8 byte count exceeds `maxChunkUTF8`, respecting the `\r\n` invariant.
6. Propagate any splits upward, updating `summary` at each level bottom-up.

After the operation, `rope.content` SHALL equal the pre-insert content with the string inserted at the correct UTF-16 position, and `rope.utf16Count` SHALL be `priorCount + string.utf16.count`.

#### Scenario: Insert at position 0 (beginning)
- **WHEN** `"prefix"` is inserted at offset 0 in a rope containing `"content"`
- **THEN** `rope.content == "prefixcontent"` and `utf16Count` reflects the combined length

#### Scenario: Insert at end
- **WHEN** a string is inserted at `utf16Offset == rope.utf16Count`
- **THEN** the string is appended and content is the concatenation of original + inserted

#### Scenario: Insert in the middle
- **WHEN** `"|"` is inserted at UTF-16 offset 3 in `TextRope("hello")`
- **THEN** `rope.content == "hel|lo"`

#### Scenario: Insert triggers leaf split
- **WHEN** inserting content that causes a leaf to exceed `maxChunkUTF8` bytes
- **THEN** the rope splits the leaf into two or more chunks and all summaries remain correct

#### Scenario: Insert preserves the \r\n invariant across splits
- **WHEN** an insert at a position causes a split immediately before a `\n` that follows a `\r`
- **THEN** the split point is adjusted so that `\r` and `\n` remain in the same chunk

#### Scenario: Insert on a shared rope does not affect the original copy
- **WHEN** rope `a` is copied to `b` and an insert is performed on `b`
- **THEN** `a.content` is unchanged and `a.utf16Count` equals its pre-copy value

#### Scenario: Summary is correct after insert
- **WHEN** any insert operation is performed
- **THEN** `rope.utf16Count == rope.content.utf16.count` and `rope.utf8Count == rope.content.utf8.count`

---

### Requirement: delete(in:) removes a UTF-16 range with correct summary propagation and leaf merging
`TextRope.mutating func delete(in utf16Range: NSRange)` SHALL:
1. Call `ensureUnique()` on the rope.
2. Navigate to the start and end leaves of the range.
3. COW-copy every node along both descent paths.
4. Remove the content from affected leaf chunks.
5. Merge undersized leaves (UTF-8 byte count below `minChunkUTF8`) with siblings.
6. Propagate merges and summary updates upward.
7. Preserve the always-rooted invariant: deleting all content SHALL produce an empty leaf root, not `nil`.

After the operation, `rope.content` SHALL equal the pre-delete content with the specified UTF-16 range removed, and `rope.utf16Count` SHALL be `priorCount - utf16Range.length`.

#### Scenario: Delete within a single leaf
- **WHEN** `delete(in: NSRange(location: 1, length: 3))` is performed on a rope containing `"hello"`
- **THEN** `rope.content == "ho"`

#### Scenario: Delete spanning multiple leaves
- **WHEN** the delete range spans a chunk boundary
- **THEN** all content within the range is removed and no content outside the range is affected

#### Scenario: Delete all content leaves an empty leaf root
- **WHEN** `delete(in: NSRange(location: 0, length: rope.utf16Count))` is performed on any non-empty rope
- **THEN** `rope.isEmpty == true` and `root` is still a non-nil empty leaf (always-rooted invariant)

#### Scenario: Delete triggers leaf merge
- **WHEN** a delete causes a leaf to fall below `minChunkUTF8` bytes
- **THEN** the leaf is merged with a sibling and all summaries remain correct

#### Scenario: Delete on a shared rope does not affect the original copy
- **WHEN** rope `a` is copied to `b` and a delete is performed on `b`
- **THEN** `a.content` is unchanged

#### Scenario: Summary is correct after delete
- **WHEN** any delete operation is performed
- **THEN** `rope.utf16Count == rope.content.utf16.count` and `rope.utf8Count == rope.content.utf8.count`

---

### Requirement: replace(range:with:) replaces a UTF-16 range with a new string
`TextRope.mutating func replace(range utf16Range: NSRange, with string: String)` SHALL remove the content in `utf16Range` and insert `string` at the start of that range. The operation SHALL be semantically equivalent to a `delete` followed by an `insert`. Summary SHALL be correct after the operation.

#### Scenario: Replace with shorter string
- **WHEN** the UTF-16 range of `"world"` in `TextRope("hello world")` is replaced with `"there"`
- **THEN** `rope.content == "hello there"`

#### Scenario: Replace with longer string
- **WHEN** `"hi"` in a rope is replaced with `"hello world"`
- **THEN** `rope.content` contains the longer replacement at the correct position

#### Scenario: Replace with empty string is equivalent to delete
- **WHEN** `replace(range:with: "")` is called
- **THEN** the result equals `delete(in: range)` applied to the same rope

#### Scenario: Replace empty range with a string is equivalent to insert
- **WHEN** `replace(range: NSRange(location: 3, length: 0), with: "X")` is called
- **THEN** the result equals `insert("X", at: 3)` applied to the same rope

#### Scenario: Summary is correct after replace
- **WHEN** any replace operation is performed
- **THEN** `rope.utf16Count == rope.content.utf16.count` and `rope.utf8Count == rope.content.utf8.count`

#### Scenario: Replace on a shared rope does not affect the original copy
- **WHEN** rope `a` is copied to `b` and a replace is performed on `b`
- **THEN** `a.content` is unchanged
