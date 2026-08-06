# rope-buffer-drift Specification

## Purpose
Pins `RopeBuffer` — and for reads, `SendableRopeBuffer` — to `MutableStringBuffer` by direct comparison: every insert, delete, replace, and sequential-operation scenario runs against both buffer kinds with identical initial state and asserts identical `content` and `selectedRange` after every step, and every composed-sequence read — surrogate halves, combining marks, ZWJ chains, and regional-indicator runs long enough to exceed any internal read window — must return exactly what the Foundation-backed oracle returns, cross-platform with no macOS gating. The suite exists so a rope-side divergence surfaces as a failing drift test instead of a silent content defect.
## Requirements
### Requirement: Drift tests prove RopeBuffer insert selection equivalence with MutableStringBuffer
For every insert operation scenario, applying the same `insert(_:at:)` call to both a `RopeBuffer` and a `MutableStringBuffer` with identical initial state SHALL produce identical `content` and `selectedRange` afterwards.

#### Scenario: Insert before insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `insert("XX", at: 2)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert at insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `insert("XX", at: 5)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert after insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `insert("XX", at: 7)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert before selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 3}`
- **AND** `insert("XX", at: 2)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert at selection start
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 3)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert within selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 5)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert at selection end
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 7)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert after selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 9)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

### Requirement: Drift tests prove RopeBuffer delete selection equivalence with MutableStringBuffer
For every delete operation scenario, applying the same `delete(in:)` call to both a `RopeBuffer` and a `MutableStringBuffer` with identical initial state SHALL produce identical `content` and `selectedRange` afterwards.

#### Scenario: Delete before insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `delete(in: {1, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete after insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `delete(in: {7, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete across insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `delete(in: {3, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete within selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {2, 6}`
- **AND** `delete(in: {4, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete overlapping selection start
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {4, 3}`
- **AND** `delete(in: {2, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete overlapping selection end
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {4, 3}`
- **AND** `delete(in: {5, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete entire selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `delete(in: {3, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete encompassing selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {4, 2}`
- **AND** `delete(in: {2, 6})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete before selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 3}`
- **AND** `delete(in: {1, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete after selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {2, 3}`
- **AND** `delete(in: {7, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

### Requirement: Drift tests prove RopeBuffer sequential operation equivalence with MutableStringBuffer
Applying a sequence of mixed insert, delete, and replace operations to both buffers SHALL produce identical `content` and `selectedRange` after every intermediate step, not just at the end.

#### Scenario: Sequential inserts with selection
- **WHEN** both buffers start with content `"abcdefghij"` and `selectedRange = {3, 4}`
- **AND** three sequential inserts are applied at offsets before, within, and after the selection
- **THEN** both buffers SHALL have identical `content` and `selectedRange` after each insert

#### Scenario: Mixed insert and delete operations
- **WHEN** both buffers start with identical content and selection
- **AND** a sequence of insert, delete, and insert operations is applied
- **THEN** both buffers SHALL have identical `content` and `selectedRange` after each operation

### Requirement: Drift tests prove RopeBuffer replace selection equivalence with MutableStringBuffer
For replace operations, applying the same `replace(range:with:)` call to both buffers SHALL produce identical `content` and `selectedRange` afterwards.

#### Scenario: Replace before selection
- **WHEN** both buffers start with identical content and `selectedRange` containing a selection
- **AND** `replace(range:with:)` is applied before the selection on both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Replace overlapping selection
- **WHEN** both buffers start with identical content and a selection range
- **AND** `replace(range:with:)` overlaps the selection on both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Replace after selection
- **WHEN** both buffers start with identical content and a selection range
- **AND** `replace(range:with:)` is applied after the selection on both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

### Requirement: Drift tests are cross-platform
The `RopeBufferDriftTests` SHALL NOT require `#if os(macOS)` gating because both `RopeBuffer` and `MutableStringBuffer` are cross-platform types. The tests MUST run on all platforms supported by Swift Package Manager.

#### Scenario: No platform gate
- **WHEN** the drift test file is compiled
- **THEN** it SHALL NOT contain `#if os(macOS)` or any platform-conditional compilation
- **AND** all tests SHALL execute on macOS and Linux

### Requirement: Drift tests prove composed-sequence read equivalence with MutableStringBuffer

For every read scenario, calling `content(in:)` or `unsafeCharacter(at:)` on a `RopeBuffer` and on a `SendableRopeBuffer` holding the same content SHALL return exactly what `MutableStringBuffer` returns for the same call. The drift tests SHALL compare against `MutableStringBuffer` (Foundation as the oracle) rather than hardcoded expectations, except where a defect repro requires an absolute anchor. Both rope-backed buffer types MUST be asserted in the same test, since both delegate to the same `TextRope` read path.

#### Scenario: Surrogate halves
- **WHEN** `content(in:)` and `unsafeCharacter(at:)` are called at every offset of `"a😀b"`
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

#### Scenario: Combining marks
- **WHEN** `content(in:)` and `unsafeCharacter(at:)` are called at every offset of `"e\u{301}b"`
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

#### Scenario: Partial grapheme ranges on a multi-chunk rope
- **WHEN** reads target offsets around a composed sequence that straddles an internal chunk boundary
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

### Requirement: Drift tests prove regional indicator read equivalence with MutableStringBuffer

The drift suite SHALL cover UAX #29 GB12/GB13 regional indicator pairing across a run long enough to exceed any internal read window, at every offset — this is the coverage whose absence let a content-visible divergence ship.

#### Scenario: Flag run divergence repro
- **WHEN** both buffer kinds are created with `String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)` and `unsafeCharacter(at: 130)` is called
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return `"🇩🇪"`, identical to `MutableStringBuffer`

#### Scenario: Every offset of a long flag run
- **WHEN** both buffer kinds are created with a run of 100 identical flags (400 UTF-16 units) and every offset in `0..<400` is read via `unsafeCharacter(at:)`
- **THEN** every result SHALL equal the `MutableStringBuffer` result at that offset

#### Scenario: Ranged reads over a flag run
- **WHEN** `content(in:)` is called with ranges that sit inside, span, start mid-flag on a trail surrogate, and end inside a regional indicator run
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

#### Scenario: Flag run mixed with surrounding prose
- **WHEN** a flag run follows several hundred UTF-16 units of ASCII text, so a non-regional-indicator character sits immediately left of the run
- **THEN** reads at every offset in and around the run SHALL match `MutableStringBuffer`

#### Scenario: Odd-length and lone regional indicators
- **WHEN** the document contains an odd-length regional indicator run and a lone regional indicator between ASCII characters
- **THEN** reads at every affected offset SHALL match `MutableStringBuffer`

#### Scenario: Flag run exceeding the internal backward-walk cap
- **WHEN** both buffer kinds hold a run of more than 2,048 consecutive identical flags (exceeding the rope's fixed 4,096-UTF-16-unit backward-walk cap) and reads are sampled at offsets across the run
- **THEN** every result SHALL equal the `MutableStringBuffer` result at that offset
- **AND** no assertion or trap SHALL fire in any build configuration — the silent full-document fallback is exercised as an ordinary path

### Requirement: Drift tests pin the composed-sequence rules that are unaffected by windowing

Combining marks and ZWJ chains are locally decidable and are handled by the read window's edge-touch retry, not by regional indicator anchoring. The drift suite SHALL pin them at document positions far beyond any internal window radius, so that a future change to the windowing strategy surfaces as a failing test rather than as another silent content defect.

#### Scenario: ZWJ chain far into the document
- **WHEN** a document repeats a ZWJ emoji sequence (e.g. 👨‍👩‍👧‍👦) past offset 130 and reads target offsets inside those sequences
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the complete sequence, identical to `MutableStringBuffer`

#### Scenario: Combining marks far into the document
- **WHEN** a document repeats base-plus-combining-mark sequences past offset 130 and reads target the base or mark offsets
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the complete composed sequence, identical to `MutableStringBuffer`

#### Scenario: Emoji modifier sequence far into the document
- **WHEN** a document repeats an emoji-plus-skin-tone-modifier sequence past offset 130 and reads target any offset inside it
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the complete sequence, identical to `MutableStringBuffer`

### Requirement: Composed-read drift tests are cross-platform

The composed-sequence drift tests SHALL NOT require `#if os(macOS)` gating, consistent with the rest of `RopeBufferDriftTests` — `RopeBuffer`, `SendableRopeBuffer`, and `MutableStringBuffer` are all cross-platform types.

#### Scenario: No platform gate
- **WHEN** the composed-read drift tests are compiled
- **THEN** they SHALL NOT contain `#if os(macOS)` or any platform-conditional compilation

### Requirement: Drift tests prove mixed-content every-offset point-read equivalence

The drift suite SHALL sweep `unsafeCharacter(at:)` at **every** UTF-16 offset of a single document that interleaves printable ASCII with emoji (surrogate pairs), combining marks, ZWJ chains, CRLF line breaks, and regional indicator runs — each non-ASCII feature bracketed by ASCII on both sides — comparing `RopeBuffer` and `SendableRopeBuffer` against `MutableStringBuffer` at every offset. The existing read-drift requirements each sweep a single feature per document and cover no CRLF reads; this combined sweep exists so that every boundary between a simple ASCII context and a complex cluster context — the offsets where a read implementation must decide between a cheap local answer and full composed-sequence expansion — is pinned against the Foundation-backed oracle, and a divergence introduced by any internal read specialization surfaces as a failing drift test rather than a silent content defect.

#### Scenario: Every offset of a mixed-content document
- **WHEN** both rope buffer kinds and a `MutableStringBuffer` hold a document interleaving ASCII prose with 😀, `e\u{301}`, a ZWJ emoji chain, `\r\n` pairs, a regional indicator run, and a lone regional indicator, and `unsafeCharacter(at:)` is called at every UTF-16 offset
- **THEN** every result from `RopeBuffer` and `SendableRopeBuffer` SHALL equal the `MutableStringBuffer` result at that offset

#### Scenario: ASCII offsets adjacent to non-ASCII content
- **WHEN** reads target printable ASCII units that sit immediately before or after a non-ASCII feature — including a single ASCII character wedged between two non-ASCII features, and the ASCII characters directly surrounding a `\r\n` pair
- **THEN** every result SHALL equal the `MutableStringBuffer` result at that offset

#### Scenario: CRLF offsets match the oracle
- **WHEN** `unsafeCharacter(at:)` is called at the `\r` offset and at the `\n` offset of a `\r\n` pair inside the mixed document
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return exactly what `MutableStringBuffer` returns at those offsets, whatever the platform's `NSString` answers

#### Scenario: Document edges of a mixed document
- **WHEN** the swept document starts and ends with non-ASCII content, and additionally an all-ASCII document is swept at offset `0` and its final offset
- **THEN** every result SHALL equal the `MutableStringBuffer` result at that offset

### Requirement: Drift tests prove text-analysis query equivalence with MutableStringBuffer

For every text-analysis scenario, calling `lineRange(for:)` or `wordRange(for:)` on a `RopeBuffer` and on a `SendableRopeBuffer` holding the same content SHALL return exactly what `MutableStringBuffer` returns for the same call. The drift tests SHALL compare against `MutableStringBuffer` (Foundation as the oracle) rather than hardcoded expectations, and both rope-backed buffer types MUST be asserted in the same test — `SendableRopeBuffer` previously inherited a different (full-document default) implementation than `RopeBuffer`, so single-type coverage would leave the other free to drift.

#### Scenario: Line delimiter zoo

- **WHEN** documents delimited by `\n`, `\r`, `\r\n`, `U+0085` (NEL), `U+2028` (LS), and `U+2029` (PS) — and a document mixing them — are queried via `lineRange(for:)` with zero-length ranges at delimiter-adjacent offsets, ranges inside a line, and ranges spanning multiple lines
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: CRLF straddling a chunk seam

- **WHEN** both rope buffer kinds hold an identical document larger than 4 KiB (so the rope has multiple leaves) with CRLF pairs placed near leaf boundaries, and `lineRange(for:)` queries force the scan across those seams — including a zero-length range between a `\r` and its `\n`
- **THEN** every result SHALL equal the `MutableStringBuffer` result for the same range

#### Scenario: Line queries at document edges

- **WHEN** `lineRange(for:)` is called with ranges at the document start, the zero-length range at the document end, a range ending exactly on a line start, a final line without a terminator, and on a delimiter-free document
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: Word zoo

- **WHEN** `wordRange(for:)` is called on words with apostrophes and hyphens, emoji words, emoji adjacent to letters, and a word longer than 256 UTF-16 units, with zero-length ranges at word starts, ends, and interiors
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: Whitespace runs

- **WHEN** `wordRange(for:)` is called with ranges inside whitespace runs — including a run whose nearest word lies hundreds of UTF-16 units away, and an all-whitespace document
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same range as `MutableStringBuffer` for every case

#### Scenario: Out-of-bounds queries throw identically

- **WHEN** `lineRange(for:)` and `wordRange(for:)` are called with a range past the document end, a negative location, and `NSNotFound`
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL throw `BufferAccessFailure.outOfRange` exactly where `MutableStringBuffer` throws it

### Requirement: Drift content assertions are byte-exact

Every drift assertion that compares `content` between a rope-backed buffer (`RopeBuffer` or `SendableRopeBuffer`) and the `MutableStringBuffer` oracle SHALL compare **UTF-8 code units**, not Swift `String` equality alone.

Swift `String ==` decides by Unicode canonical equivalence, so a rope-side change that composed, decomposed, or canonically reordered content would produce text the oracle does not hold while every `String`-based drift assertion still passed. The oracle's own equality is already code-unit (`MutableStringBuffer.==` goes through `NSString.isEqual`), so a `String`-only drift assertion is strictly weaker than the equivalence it claims to prove — it cannot detect precisely the divergence class the rope's storage makes possible.

The byte-exact assertion SHALL **supplement**, not replace, the `String` assertion. The `String` comparison stays because it prints readable text on failure; the byte comparison decides fidelity. Keeping both also localizes the diagnosis: a failure that is `String`-equal but byte-unequal is specifically a normalization or canonical-ordering divergence.

This applies at minimum to:

- the shared drift helper in `Tests/TextBufferTests/RopeBufferDriftTests.swift` through which the insert, delete, replace, and sequential-operation scenarios compare buffer pairs, and
- `assertUndoEquivalence(...)` and `assertSendableUndoEquivalence(...)` in `Sources/TextBufferTesting/AssertUndoEquivalence.swift`, through which the undo-equivalence suites compare a rope-backed subject against the `MutableStringBuffer`-backed reference after every step.

Content comparisons that are already byte-exact — the transfer round-trip assertions and the stress-suite oracle comparison — SHALL remain so.

#### Scenario: Shared drift helper compares content byte-exactly

- **WHEN** a drift scenario applies the same operation to a `RopeBuffer` and a `MutableStringBuffer` and asserts equivalence through the shared helper
- **THEN** the helper SHALL assert that the two contents have identical UTF-8 code unit sequences, in addition to its existing `String` and `selectedRange` assertions

#### Scenario: Undo-equivalence helpers compare content byte-exactly

- **WHEN** `assertUndoEquivalence` or `assertSendableUndoEquivalence` replays a `BufferStep` sequence against a reference and a subject
- **THEN** after every step the two contents SHALL be asserted equal as UTF-8 code unit sequences, in addition to the existing `String` and `selectedRange` assertions, and the failure message SHALL identify the step index

#### Scenario: A canonical-only assertion would mask normalization divergence

- **WHEN** a rope-backed buffer holds content that is canonically equivalent to the oracle's but code-unit different — for example combining marks in a different canonical order — after an otherwise identical operation sequence
- **THEN** the drift suite SHALL fail, and it SHALL fail on the byte comparison; an assertion set that passes on such a pair does not satisfy this requirement

