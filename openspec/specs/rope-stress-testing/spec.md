# rope-stress-testing Specification

## Purpose
TBD - created by archiving change m2-rope-verification. Update Purpose after archive.
## Requirements
### Requirement: Stress test with String oracle
The test suite SHALL apply at least 10,000 random operations (insert, delete, replace) to both a `TextRope` and an equivalent `String` oracle. After each operation, the test MUST assert that `rope.content == oracle`, `rope.utf16Count == oracle.utf16.count`, and `rope.utf8Count == oracle.utf8.count`. Any mismatch MUST cause an immediate test failure with the operation index and seed reported.

#### Scenario: 10K random operations produce no mismatches
- **WHEN** 10,000 random insert/delete/replace operations are applied to both a `TextRope` and a `String` using the same seeded RNG
- **THEN** after every operation, `rope.content` equals the oracle string, and `rope.utf16Count` and `rope.utf8Count` match the oracle's counts

#### Scenario: Failure reports seed and operation index
- **WHEN** a mismatch is detected between rope and oracle during the stress test
- **THEN** the failure message includes the RNG seed and the zero-based operation index so the exact sequence can be replayed

### Requirement: Deterministic reproducibility via seeded RNG
The stress test MUST use a seeded random number generator so that a failing sequence can be replayed exactly. The default seed SHALL be a hardcoded constant for CI determinism. The seed MUST be logged at the start of the test run.

#### Scenario: Same seed produces identical operation sequence
- **WHEN** the stress test is run twice with the same seed
- **THEN** the exact same sequence of operations is generated both times, producing identical rope content

#### Scenario: Seed is logged at test start
- **WHEN** the stress test begins execution
- **THEN** the seed value is printed or logged before any operations are applied

### Requirement: Mixed character encoding in random operations
The random operation generator MUST draw inserted strings from a character pool that includes ASCII characters, multi-byte Latin characters (2-byte UTF-8, e.g., accented vowels), emoji with surrogate pairs (4-byte UTF-8), CJK characters (3-byte UTF-8), and `\r\n` line endings. This ensures all encoding paths in TextRope are exercised under random mutation.

#### Scenario: Stress test inserts contain multi-byte characters
- **WHEN** the stress test completes 10,000 operations
- **THEN** the operation log includes insertions containing ASCII, multi-byte Latin, emoji, CJK, and `\r\n` sequences

#### Scenario: Content equality holds for multi-byte insertions
- **WHEN** a random insert places a 4-byte emoji character into the rope
- **THEN** `rope.content` still equals the oracle string, and `rope.utf16Count` accounts for the surrogate pair (2 UTF-16 code units per emoji)

### Requirement: Operation distribution covers insert, delete, and replace
The random operation generator MUST produce a mix of inserts, deletes, and replaces. No single operation type SHALL constitute more than 60% of total operations. All three operation types MUST appear in every stress test run.

#### Scenario: All operation types are exercised
- **WHEN** 10,000 random operations are generated
- **THEN** the generated sequence contains at least one insert, at least one delete, and at least one replace operation

#### Scenario: No operation type dominates excessively
- **WHEN** 10,000 random operations are generated
- **THEN** each of insert, delete, and replace constitutes between 15% and 60% of total operations

### Requirement: Tree structure validation under stress
The stress test MUST validate the internal tree structure of the rope. Validation SHALL confirm: every inner node's summary equals the sum of its children's summaries, every leaf's summary equals `Summary.of(chunk)`, tree height is consistent (all leaves at the same depth), no grapheme cluster — including `\r\n` — spans a chunk boundary, and every leaf's chunk size satisfies the grapheme-first chunk-size bounds (ADR-012): at most `maxChunkUTF8` unless the chunk is a single grapheme cluster larger than `maxChunkUTF8`, and at least `minChunkUTF8` unless per-leaf boundary starvation provably applies (no adjacent sibling can absorb the leaf and the combined slice has no `Character` boundary in its legal window). The starvation check is an exact predicate evaluated per leaf — validation MUST NOT use a fuzzy byte tolerance or skip undersized leaves.

At least one seeded run — a dedicated run of at least 2,000 mixed operations — MUST validate the full tree structure after **every** operation, not on a sampled interval. Sampled validation MAY be used for the remaining runs to keep suite runtime bounded, but MUST NOT be the only validation performed by the suite: structural violations produced by redistribution are transient and are repaired or masked by subsequent operations, so a 1-in-100 sample can miss them indefinitely. Validation MUST also occur at the end of every stress run. A validation failure MUST report the seed and the zero-based operation index.

#### Scenario: Per-operation validation on a dedicated seed
- **WHEN** the stress suite runs
- **THEN** a dedicated seeded run of at least 2,000 mixed operations SHALL call full tree-invariant validation after every single operation, and its failures SHALL name the seed and operation index

#### Scenario: A transient oversized leaf fails at the operation that caused it
- **WHEN** an operation leaves a multi-character leaf larger than `maxChunkUTF8` and a later operation would repair or hide it
- **THEN** the per-operation run SHALL fail at the causing operation rather than at a later sampled checkpoint or not at all

#### Scenario: Undersized leaves are judged against the starvation predicate, not skipped
- **WHEN** validation encounters a leaf below `minChunkUTF8` in a rope whose root is an inner node
- **THEN** it SHALL fail unless every adjacent sibling both exceeds the merge capacity and shares no `Character` boundary inside the legal redistribution window

#### Scenario: Oversized leaves are judged against the whole-cluster exception
- **WHEN** validation encounters a leaf above `maxChunkUTF8`
- **THEN** it SHALL fail unless the leaf's chunk consists of exactly one grapheme cluster

#### Scenario: Tree structure is valid after 10K operations
- **WHEN** 10,000 random operations complete
- **THEN** a full tree traversal confirms summary consistency at every node, uniform leaf depth, chunk sizes within the grapheme-first bounds, and no `\r\n` splits across chunk boundaries

#### Scenario: Periodic validation during stress test
- **WHEN** a stress run uses sampled validation
- **THEN** tree structure validation occurs at regular intervals (e.g. every 100 operations) in addition to the final validation, with the sampling rationale documented at the call site

### Requirement: Construction round-trip correctness
The test suite MUST verify that constructing a `TextRope` from a string and reading back its `content` produces the original string. This MUST be tested for: empty string, a string smaller than one chunk, a string exactly equal to `maxChunkUTF8` bytes, a multi-chunk string, and a very large string (100KB+).

#### Scenario: Empty string round-trip
- **WHEN** `TextRope("")` is constructed
- **THEN** `content` is `""`, `utf16Count` is `0`, `utf8Count` is `0`, and `isEmpty` is `true`

#### Scenario: Sub-chunk string round-trip
- **WHEN** `TextRope("hello")` is constructed
- **THEN** `content` is `"hello"` and summary counts match

#### Scenario: Multi-chunk string round-trip
- **WHEN** a `TextRope` is constructed from a string exceeding `maxChunkUTF8` bytes
- **THEN** `content` equals the original string and the tree has multiple leaves

#### Scenario: Large string round-trip
- **WHEN** a `TextRope` is constructed from a 100KB+ string
- **THEN** `content` equals the original string and all summary counts match

### Requirement: Content round-trip across encodings
The test suite MUST verify content fidelity for: pure ASCII text, multi-byte Latin text (accented characters), emoji text (surrogate pairs in UTF-16), CJK text, and mixed-encoding text containing all categories. After construction and readback, content MUST be byte-identical to the input.

#### Scenario: ASCII content round-trip
- **WHEN** a `TextRope` is constructed from a pure ASCII string
- **THEN** `content` equals the original string

#### Scenario: Multi-byte Latin round-trip
- **WHEN** a `TextRope` is constructed from a string of accented Latin characters (e.g., `"àáâãäåèéêë"`)
- **THEN** `content` equals the original string and `utf8Count > utf16Count`

#### Scenario: Emoji round-trip
- **WHEN** a `TextRope` is constructed from a string of emoji characters (e.g., `"🎉🚀💡🌍"`)
- **THEN** `content` equals the original string and `utf16Count` is twice the character count (each emoji is one surrogate pair)

#### Scenario: CJK round-trip
- **WHEN** a `TextRope` is constructed from CJK text (e.g., `"你好世界"`)
- **THEN** `content` equals the original string and `utf8Count` is 3× the character count

#### Scenario: Mixed encoding round-trip
- **WHEN** a `TextRope` is constructed from a string mixing ASCII, Latin, emoji, and CJK
- **THEN** `content` equals the original string with all encoding categories preserved

### Requirement: COW independence under mutation
The test suite MUST verify that when a `TextRope` is copied and one copy is mutated, the other copy is unaffected. This MUST be tested with insert, delete, and replace operations on the mutated copy.

#### Scenario: Insert on copy does not affect original
- **WHEN** `var a = TextRope(largeString)`, `var b = a`, then `b.insert("x", at: 0)`
- **THEN** `a.content` equals `largeString` and `b.content` equals `"x" + largeString`

#### Scenario: Delete on copy does not affect original
- **WHEN** `var a = TextRope(largeString)`, `var b = a`, then `b.delete(in: NSRange(location: 0, length: 1))`
- **THEN** `a.content` equals `largeString` and `b.content` equals `largeString` with the first character removed

#### Scenario: Multiple mutations on copy preserve original
- **WHEN** a rope is copied and the copy undergoes 100 random mutations
- **THEN** the original rope's content remains unchanged throughout

