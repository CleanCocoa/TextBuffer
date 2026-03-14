## ADDED Requirements

### Requirement: Tree descent to UTF-16 offset
The `TextRope` SHALL provide an internal `findLeaf(utf16Offset:)` method that descends the B-tree in O(log n) time to locate the leaf node containing the given UTF-16 code unit offset. The method MUST return the target leaf node and the remaining UTF-16 offset within that leaf. At each inner node, the descent MUST use the cumulative `summary.utf16` counts of child nodes to determine which child contains the target offset.

#### Scenario: Single-leaf rope navigation
- **WHEN** a `TextRope` contains text within a single leaf and `findLeaf(utf16Offset: k)` is called where `0 <= k <= chunk.utf16.count`
- **THEN** the method MUST return the root leaf node with remaining offset `k`

#### Scenario: Multi-leaf rope navigation to first leaf
- **WHEN** a `TextRope` spans multiple leaves and `findLeaf(utf16Offset: k)` is called where `k < firstLeaf.summary.utf16`
- **THEN** the method MUST return the first leaf with remaining offset `k`

#### Scenario: Multi-leaf rope navigation to interior leaf
- **WHEN** a `TextRope` spans multiple leaves and `findLeaf(utf16Offset: k)` is called where `k` falls within an interior leaf (not the first or last)
- **THEN** the method MUST descend using cumulative `summary.utf16` counts and return the correct interior leaf with the remaining offset relative to that leaf's start

#### Scenario: Navigation to end-of-document
- **WHEN** `findLeaf(utf16Offset: utf16Count)` is called with the offset equal to the total UTF-16 count of the rope
- **THEN** the method MUST return the last leaf with remaining offset equal to that leaf's `summary.utf16`

#### Scenario: Offset beyond document bounds
- **WHEN** `findLeaf(utf16Offset: k)` is called where `k > root.summary.utf16`
- **THEN** a precondition failure MUST occur

### Requirement: Leaf-level UTF-16 to String.Index translation
Within a leaf node, the remaining UTF-16 offset MUST be translated to a `String.Index` by indexing into the chunk's `utf16` view. This translation is O(chunk_size), bounded by `Node.maxChunkUTF8`.

#### Scenario: ASCII-only chunk translation
- **WHEN** a leaf contains only ASCII text and a UTF-16 offset `k` is translated
- **THEN** the resulting `String.Index` MUST correspond to the `k`-th character (since ASCII characters are 1 UTF-16 code unit each)

#### Scenario: Multi-byte character chunk translation
- **WHEN** a leaf contains multi-byte characters (e.g., accented Latin, CJK) that are each 1 UTF-16 code unit but multiple UTF-8 bytes
- **THEN** the resulting `String.Index` MUST correctly account for the difference between UTF-8 byte positions and UTF-16 code unit positions

#### Scenario: Surrogate pair chunk translation
- **WHEN** a leaf contains characters above U+FFFF (e.g., emoji 🎉) that require 2 UTF-16 code units (surrogate pairs)
- **THEN** the UTF-16 offset MUST correctly translate to a `String.Index` that respects surrogate pair boundaries

### Requirement: Content extraction by UTF-16 range
`TextRope` SHALL provide a public `content(in utf16Range: NSRange) -> String` method that returns the substring corresponding to the given UTF-16 range. The extraction MUST be O(log n + k) where k is the length of the extracted content.

#### Scenario: Range within a single leaf
- **WHEN** `content(in:)` is called with a range that falls entirely within one leaf
- **THEN** the method MUST return the correct substring from that leaf's chunk

#### Scenario: Range spanning multiple leaves
- **WHEN** `content(in:)` is called with a range that spans two or more leaves
- **THEN** the method MUST concatenate the suffix of the first leaf, the full content of any intermediate leaves, and the prefix of the last leaf, returning the correct combined substring

#### Scenario: Empty range
- **WHEN** `content(in:)` is called with `NSRange(location: k, length: 0)` where `0 <= k <= utf16Count`
- **THEN** the method MUST return an empty string `""`

#### Scenario: Full document range
- **WHEN** `content(in:)` is called with `NSRange(location: 0, length: utf16Count)`
- **THEN** the method MUST return a string equal to the rope's `content` property

#### Scenario: Range at document boundaries
- **WHEN** `content(in:)` is called with a range starting at offset 0 or ending at `utf16Count`
- **THEN** the method MUST correctly handle these boundary positions without error

#### Scenario: Range with multi-byte and surrogate pair characters
- **WHEN** `content(in:)` is called with a range that includes emoji (surrogate pairs), accented characters, or CJK characters
- **THEN** the extracted content MUST be character-correct, with UTF-16 offsets properly resolved to character boundaries

#### Scenario: Content extraction on empty rope
- **WHEN** `content(in:)` is called on an empty `TextRope` with `NSRange(location: 0, length: 0)`
- **THEN** the method MUST return `""`

#### Scenario: Range exceeds document bounds
- **WHEN** `content(in:)` is called with a range where `location + length > utf16Count`
- **THEN** a precondition failure MUST occur

### Requirement: Navigation does not mutate the rope
The `findLeaf(utf16Offset:)` method and `content(in:)` method MUST be non-mutating. Navigation is a read-only operation that SHALL NOT trigger COW copies or modify any node in the tree.

#### Scenario: Navigation preserves shared references
- **WHEN** a `TextRope` value is copied (sharing the root via COW) and `content(in:)` is called on either copy
- **THEN** both copies MUST continue to share the same underlying tree structure — no COW copy SHALL be triggered
