## MODIFIED Requirements

### Requirement: Mixed character encoding in random operations

The random operation generator MUST draw inserted strings from a character pool that includes ASCII characters, multi-byte Latin characters (2-byte UTF-8, e.g., accented vowels), emoji with surrogate pairs (4-byte UTF-8), CJK characters (3-byte UTF-8), and `\r\n` line endings. This ensures all encoding paths in TextRope are exercised under random mutation.

The pool MUST also include lone grapheme extenders — at least a combining mark (`U+0301`), a zero-width joiner (`U+200D`), and a variation selector (`U+FE0F`) — as standalone insert operands. Extenders join *leftward* with whatever `Character` precedes their insertion point, so random placement can form a grapheme cluster across a pre-existing leaf adjacency — the DEF-016 class that a pool of self-contained characters can never produce. The dedicated per-operation-validated run SHALL draw from this extended pool, so adjacency-formed clusters are exercised under per-operation tree-invariant validation rather than only by dedicated regression tests.

> Note (fix-delete-merge-starvation): this supersedes the 2026-08-04 deferral note left by `fix-grapheme-seam-repair` — the extender mandate was deferred because the extended pool's RNG stream exposed the then-open DEF-017 (delete-path merge starvation) across all five pinned seeds; with DEF-017 fixed in this change, the mandate lands and the deferral note is removed.

Because combining marks make Swift `String` equality (canonical equivalence) weaker than byte equality, at least the dedicated per-operation-validated run SHALL compare rope content and oracle at the code-unit level (e.g. UTF-8 byte sequences), in addition to the existing `content`, `utf16Count`, and `utf8Count` assertions, so that byte-level fidelity cannot be masked by canonically equivalent reorderings.

#### Scenario: Stress test inserts contain multi-byte characters
- **WHEN** the stress test completes 10,000 operations
- **THEN** the operation log includes insertions containing ASCII, multi-byte Latin, emoji, CJK, and `\r\n` sequences

#### Scenario: Content equality holds for multi-byte insertions
- **WHEN** a random insert places a 4-byte emoji character into the rope
- **THEN** `rope.content` still equals the oracle string, and `rope.utf16Count` accounts for the surrogate pair (2 UTF-16 code units per emoji)

#### Scenario: Stress alphabet includes lone grapheme extenders as insert operands
- **WHEN** the stress suite's character pool is inspected and a stress run completes
- **THEN** the pool SHALL contain `U+0301`, `U+200D`, and `U+FE0F` as standalone operands, so random inserts can place a lone extender at any offset — including leaf boundaries — and the pinned seeds SHALL run green over this extended pool

#### Scenario: Adjacency-formed clusters are validated per operation
- **WHEN** the dedicated per-operation-validated run inserts a lone extender whose placement joins it with the `Character` before it — including across a pre-existing leaf adjacency
- **THEN** full tree-invariant validation (seam and chunk-size predicates) SHALL run after that operation and pass, failing at the causing operation index if the mutation left a seam inside a cluster or a non-starved undersized leaf

#### Scenario: Byte-exact fidelity is asserted despite canonical equivalence
- **WHEN** the dedicated per-operation-validated run compares rope content against the oracle in a pool containing combining marks
- **THEN** the comparison SHALL be code-unit-exact (equal UTF-8 byte sequences), not only Swift `String ==`, so canonically equivalent but byte-different content is reported as a failure
