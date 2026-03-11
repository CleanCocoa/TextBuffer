## ADDED Requirements

### Requirement: TextRope SHALL preserve content equality across repeated edits
Across repeated construction, navigation, insert, delete, and replace operations, `TextRope` SHALL produce the same externally visible content as an equivalent `String` oracle driven by the same sequence of edits.

#### Scenario: Repeated mixed edits preserve content equality
- **WHEN** a long sequence of insert, delete, and replace operations is applied to both a `TextRope` and an equivalent `String`
- **THEN** `rope.content` equals the oracle string after every operation

#### Scenario: Content equality holds for ASCII, multi-byte, and emoji content
- **WHEN** repeated edits involve ASCII, multi-byte Unicode, CJK, and emoji payloads
- **THEN** `rope.content` remains identical to the oracle string after every operation

---

### Requirement: TextRope SHALL preserve summary invariants under repeated edits
After any sequence of edits, the rope's cached metrics SHALL remain consistent with its materialized content.

#### Scenario: utf16Count matches materialized content
- **WHEN** any sequence of edits is applied to a `TextRope`
- **THEN** `rope.utf16Count == rope.content.utf16.count`

#### Scenario: utf8Count matches materialized content
- **WHEN** any sequence of edits is applied to a `TextRope`
- **THEN** `rope.utf8Count == rope.content.utf8.count`

#### Scenario: Summary invariants hold during randomized stress
- **WHEN** a long randomized edit sequence is applied
- **THEN** no summary drift occurs at any checkpoint

---

### Requirement: TextRope SHALL preserve copy-on-write isolation under mutation
Copying a `TextRope` by value SHALL create a logically independent rope. Mutating one copy SHALL NOT change the content or cached metrics of the other copy.

#### Scenario: Mutating a copy does not change the original content
- **WHEN** `var b = a` is created and a mutating operation is applied to `b`
- **THEN** `a.content` remains equal to the original content captured before the mutation

#### Scenario: Mutating a copy does not change the original summaries
- **WHEN** `var b = a` is created and a mutating operation is applied to `b`
- **THEN** `a.utf16Count` and `a.utf8Count` remain unchanged from their pre-mutation values

---

### Requirement: TextRope SHALL maintain chunk-splitting invariants under repeated edits
Repeated edits SHALL preserve the rope's structural invariants, including the `\r\n` split rule and the always-rooted empty state.

#### Scenario: \r\n is never split across a chunk boundary
- **WHEN** repeated edits place `\r\n` sequences near chunk boundaries
- **THEN** no chunk ends with `\r` when the next chunk begins with `\n`

#### Scenario: Deleting all content preserves always-rooted empty state
- **WHEN** repeated edits delete the entire document content
- **THEN** the rope remains always-rooted and represents an empty document without a nil root

---

### Requirement: TextRope SHALL remain correct under large randomized edit sequences
The implementation SHALL tolerate large randomized edit workloads without content corruption, summary drift, or structural invariant violations.

#### Scenario: 10,000 randomized operations complete with no mismatch
- **WHEN** 10,000 randomized insert, delete, and replace operations are applied to a `TextRope` and a `String` oracle
- **THEN** no mismatch occurs in content or cached counts at any step
