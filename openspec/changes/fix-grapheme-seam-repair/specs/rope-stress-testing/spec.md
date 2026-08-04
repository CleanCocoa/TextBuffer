## MODIFIED Requirements

### Requirement: Mixed character encoding in random operations

The random operation generator MUST draw inserted strings from a character pool that includes ASCII characters, multi-byte Latin characters (2-byte UTF-8, e.g., accented vowels), emoji with surrogate pairs (4-byte UTF-8), CJK characters (3-byte UTF-8), and `\r\n` line endings. This ensures all encoding paths in TextRope are exercised under random mutation.

Because combining marks make Swift `String` equality (canonical equivalence) weaker than byte equality, at least the dedicated per-operation-validated run SHALL compare rope content and oracle at the code-unit level (e.g. UTF-8 byte sequences), in addition to the existing `content`, `utf16Count`, and `utf8Count` assertions, so that byte-level fidelity cannot be masked by canonically equivalent reorderings.

> Note (2026-08-04): this change originally also mandated lone grapheme extenders (U+0301, U+200D, U+FE0F) in the pool to cover the DEF-016 adjacency class under random mutation. Implementing that extension exposed the distinct pre-existing DEF-017 (delete-path merge starves a leaf without consulting the other-side neighbor) across all five pinned seeds, so the extender mandate moves to DEF-017's fix change; DEF-016's own class is pinned by the dedicated `GraphemeSeamRepairTests` regression suite in the meantime.

#### Scenario: Stress test inserts contain multi-byte characters
- **WHEN** the stress test completes 10,000 operations
- **THEN** the operation log includes insertions containing ASCII, multi-byte Latin, emoji, CJK, and `\r\n` sequences

#### Scenario: Content equality holds for multi-byte insertions
- **WHEN** a random insert places a 4-byte emoji character into the rope
- **THEN** `rope.content` still equals the oracle string, and `rope.utf16Count` accounts for the surrogate pair (2 UTF-16 code units per emoji)

#### Scenario: Byte-exact fidelity is asserted despite canonical equivalence
- **WHEN** the dedicated per-operation-validated run compares rope content against the oracle in a pool containing combining marks
- **THEN** the comparison SHALL be code-unit-exact (equal UTF-8 byte sequences), not only Swift `String ==`, so canonically equivalent but byte-different content is reported as a failure
