## MODIFIED Requirements

### Requirement: Mixed character encoding in random operations

The random operation generator MUST draw inserted strings from a character pool that includes ASCII characters, multi-byte Latin characters (2-byte UTF-8, e.g., accented vowels), emoji with surrogate pairs (4-byte UTF-8), CJK characters (3-byte UTF-8), `\r\n` line endings, and **lone grapheme extenders** — at minimum a combining mark (e.g. U+0301 COMBINING ACUTE ACCENT), a zero-width joiner (U+200D), and a variation selector (U+FE0F). Extenders are operands that join *leftward* with whatever character precedes their insertion point, so random placement can form a grapheme cluster across a pre-existing leaf adjacency — the DEF-016 defect class, which a pool of self-contained characters can never produce. This ensures all encoding paths in TextRope, including adjacency-formed cluster seam repair, are exercised under random mutation.

Because combining marks make Swift `String` equality (canonical equivalence) weaker than byte equality, at least the dedicated per-operation-validated run SHALL compare rope content and oracle at the code-unit level (e.g. UTF-8 byte sequences), in addition to the existing `content`, `utf16Count`, and `utf8Count` assertions, so that byte-level fidelity cannot be masked by canonically equivalent reorderings.

#### Scenario: Stress test inserts contain multi-byte characters
- **WHEN** the stress test completes 10,000 operations
- **THEN** the operation log includes insertions containing ASCII, multi-byte Latin, emoji, CJK, and `\r\n` sequences

#### Scenario: Lone grapheme extenders appear as insert operands
- **WHEN** the stress test's character pool is sampled across a run
- **THEN** inserted strings SHALL include lone combining marks, zero-width joiners, and variation selectors, so that operations can place an extender directly after arbitrary existing content — including at leaf boundaries

#### Scenario: Adjacency-formed clusters are validated per operation
- **WHEN** the dedicated per-operation-validated seed runs with the extender-bearing pool
- **THEN** tree-invariant validation after every operation SHALL include the seam check (no grapheme cluster spans a leaf seam), so an unrepaired adjacency-formed cluster fails at the operation that caused it

#### Scenario: Content equality holds for multi-byte insertions
- **WHEN** a random insert places a 4-byte emoji character into the rope
- **THEN** `rope.content` still equals the oracle string, and `rope.utf16Count` accounts for the surrogate pair (2 UTF-16 code units per emoji)

#### Scenario: Byte-exact fidelity is asserted despite canonical equivalence
- **WHEN** the dedicated per-operation-validated run compares rope content against the oracle in a pool containing combining marks
- **THEN** the comparison SHALL be code-unit-exact (equal UTF-8 byte sequences), not only Swift `String ==`, so canonically equivalent but byte-different content is reported as a failure
