# rope-utf16-navigation Specification

## Purpose
TBD - created by archiving change m2-rope-navigation. Update Purpose after archive.
## Requirements
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

Bounds validation MUST precede the empty-range early return: a range whose location is out of bounds — past the end, negative, or `NSNotFound` — MUST cause a precondition failure even when `length == 0`. A zero-length range at an in-bounds location (`0 <= location <= utf16Count`) SHALL return `""`.

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

#### Scenario: Zero-length range at an out-of-bounds location traps
- **WHEN** `content(in:)` is called with `NSRange(location: k, length: 0)` where `k` is past the end (`k > utf16Count`), negative, or `NSNotFound`
- **THEN** a precondition failure MUST occur
- **AND** the call SHALL NOT return `""`

### Requirement: Navigation does not mutate the rope
The `findLeaf(utf16Offset:)` method and `content(in:)` method MUST be non-mutating. Navigation is a read-only operation that SHALL NOT trigger COW copies or modify any node in the tree.

#### Scenario: Navigation preserves shared references
- **WHEN** a `TextRope` value is copied (sharing the root via COW) and `content(in:)` is called on either copy
- **THEN** both copies MUST continue to share the same underlying tree structure — no COW copy SHALL be triggered

### Requirement: Composed character sequence reads match full-document NSString semantics

`TextRope` SHALL provide `composedCharacterSequences(in utf16Range: NSRange) -> String` and `composedCharacterSequence(at utf16Offset: Int) -> String`. For every rope and every in-bounds argument, the returned string MUST be identical to the result of applying `NSString.rangeOfComposedCharacterSequences(for:)` / `NSString.rangeOfComposedCharacterSequence(at:)` to the rope's **entire** content and extracting the resulting range. The result MUST NOT depend on the rope's internal chunking, tree shape, or on any window size used internally to avoid materializing the whole document.

An out-of-bounds argument MUST cause a precondition failure. Bounds validation MUST precede any zero-length early return: `composedCharacterSequences(in:)` called with a zero-length range whose location is out of bounds — past the end, negative, or `NSNotFound` — MUST trap rather than return `""`. A zero-length range at an in-bounds location (`0 <= location <= utf16Count`) SHALL return `""`.

#### Scenario: Zero-length range at an out-of-bounds location traps
- **WHEN** `composedCharacterSequences(in:)` is called with `NSRange(location: k, length: 0)` where `k` is past the end (`k > utf16Count`), negative, or `NSNotFound`
- **THEN** a precondition failure MUST occur
- **AND** the call SHALL NOT return `""`

#### Scenario: Read equals full-document expansion at every offset
- **WHEN** `composedCharacterSequence(at: k)` is called for any `k` in `0..<utf16Count`
- **THEN** the result SHALL equal `(rope.content as NSString).substring(with: (rope.content as NSString).rangeOfComposedCharacterSequence(at: k))`

#### Scenario: Read is independent of tree shape
- **WHEN** two ropes hold identical content but were built differently (single leaf versus many leaves, e.g. via bulk init versus incremental inserts)
- **THEN** `composedCharacterSequence(at: k)` SHALL return the same string from both for every `k`

#### Scenario: Surrogate pair halves resolve to the whole character
- **WHEN** `composedCharacterSequence(at:)` is called at either the lead or the trail surrogate offset of a non-BMP character such as 😀
- **THEN** the result SHALL be the complete character

#### Scenario: Combining mark sequences are returned whole
- **WHEN** the rope contains base-plus-combining-mark sequences (e.g. `e\u{301}`) and a read targets the base or the mark offset
- **THEN** the result SHALL be the complete composed sequence

#### Scenario: ZWJ emoji chains are returned whole
- **WHEN** the rope contains a ZWJ emoji sequence (e.g. 👨‍👩‍👧‍👦) and a read targets any offset inside it
- **THEN** the result SHALL be the complete sequence, regardless of how far into the document the sequence sits

### Requirement: Regional indicator pairing follows UAX #29 GB12/GB13 from the run start

Reads over regional indicator characters (`U+1F1E6...U+1F1FF`) MUST pair them per UAX #29 GB12/GB13 — counting from the start of the maximal contiguous regional indicator run, exactly as a full-document `NSString` expansion would. An internal read window MUST NOT begin strictly inside a regional indicator run; when a computed window start falls inside such a run, the implementation SHALL extend the window backward to the start of that run so that pairing parity inside the window matches pairing parity computed from the document start.

The backward walk SHALL be capped at a fixed 4,096 UTF-16 units (2,048 regional indicators); the cap is a property of the text being walked and SHALL NOT be derived from the rope's chunk geometry. When a contiguous run exceeds the cap, the implementation SHALL fall back to full-document expansion **silently** — no assertion, trap, or diagnostic in any build configuration — so the fallback is an ordinary, testable code path.

#### Scenario: Flag read beyond the internal window radius
- **WHEN** a rope holds `String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)` (🇩🇪 × 40, 160 UTF-16 units) and `composedCharacterSequence(at: 130)` is called
- **THEN** the result SHALL be `"🇩🇪"`
- **AND** it SHALL NOT be the mispaired `"🇪🇩"`

#### Scenario: Every offset of a long flag run reads correctly
- **WHEN** a rope holds a run of 100 identical flags (400 UTF-16 units) and `composedCharacterSequence(at: k)` is called for every `k` in `0..<400`
- **THEN** every result SHALL equal the full-document `NSString` expansion at that offset

#### Scenario: Regional indicator run beginning at document start
- **WHEN** the regional indicator run starts at offset 0 and a read targets an offset inside it
- **THEN** the result SHALL match full-document expansion, with the window start clamped to 0

#### Scenario: Odd-length regional indicator run
- **WHEN** the run contains an odd number of regional indicators, leaving a final unpaired regional indicator
- **THEN** reads at every offset in the run — including the unpaired trailing one — SHALL match full-document expansion

#### Scenario: Regional indicator run bounded by non-regional-indicator text
- **WHEN** a flag run is preceded and followed by ASCII text
- **THEN** pairing SHALL restart at the run start, and reads at every offset SHALL match full-document expansion

#### Scenario: Lone regional indicator
- **WHEN** a single regional indicator appears between non-regional-indicator characters
- **THEN** a read at that offset SHALL return just that regional indicator, matching full-document expansion

#### Scenario: Read range starting on a trail surrogate inside a flag
- **WHEN** `composedCharacterSequences(in:)` is called with a range whose location is the trail surrogate offset of a regional indicator inside a run
- **THEN** the returned string SHALL be the correctly paired composed sequences, matching full-document expansion

#### Scenario: Regional indicator run longer than the backward-walk cap
- **WHEN** a contiguous regional indicator run is longer than the fixed 4,096-UTF-16-unit backward-walk cap
- **THEN** the implementation SHALL fall back to full-document expansion silently, without trapping or asserting in any build configuration
- **AND** the returned string SHALL still match full-document `NSString` semantics

### Requirement: Materialized read window length matches the requested span

Any internal window materialized for a composed-sequence boundary search MUST contain exactly the number of UTF-16 code units requested for it. Under grapheme-first chunk bounds (ADR-012) a chunk seam can never fall inside a `Character`, so `content(in:)` can never mis-slice mid-cluster and a length mismatch can only mean a broken rope-internal invariant. The implementation SHALL NOT assume the length silently: it MUST verify the materialized length against the requested span before computing window-relative ranges, and on mismatch MUST trap with a precondition failure in all build configurations. It SHALL NOT clamp the range and SHALL NOT fall back to full-document expansion on mismatch — no text computed against a desynchronized window is correct to return.

#### Scenario: Window length matches in normal operation
- **WHEN** a composed-sequence read materializes an internal window of `n` requested UTF-16 code units
- **THEN** the materialized window SHALL contain exactly `n` UTF-16 code units

#### Scenario: Mismatch traps rather than being assumed away
- **WHEN** the materialized window's UTF-16 length differs from the requested span
- **THEN** a precondition failure MUST occur
- **AND** no window-relative range SHALL be computed against the desynchronized window

