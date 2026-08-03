## MODIFIED Requirements

### Requirement: TextRope is Equatable via content comparison

> Rebased on the `fix-rope-cow-and-equality-coverage` delta for this requirement, which lands first. This version carries that delta's text forward and adds the tiered summary early-out; it does not replace its coverage obligations.

`TextRope` SHALL conform to `Equatable`. Two TextRope values SHALL be equal if and only if their `content` strings are equal. Equality SHALL be independent of tree shape: two ropes holding the same characters over different leaf partitions, different child groupings, or different heights SHALL compare equal — no term of the comparison may be shape-derived.

Equality SHALL be decided in three tiers, in order:

1. **Identity.** If both values share the same root node (`lhs.root === rhs.root`), they SHALL be equal without further work.
2. **Summary early-out.** Otherwise, if the two root summaries differ in any field (`utf8`, `utf16`, or `lines`), the values SHALL be unequal. This comparison MUST be O(1) and MUST NOT materialize either rope's content.
3. **Content comparison.** Otherwise, equality SHALL be decided by comparing the materialized `content` strings.

Tier 2 is sound because every `Summary` field is a pure, additive function of the text: `utf8` is its UTF-8 byte count, `utf16` its UTF-16 code unit count, and `lines` its `\n` count. A node's summary equals the sum over its subtree, so the root summary equals that same function applied to `content`. Equal content therefore implies equal summaries, and — by contraposition — differing summaries prove differing content.

The converse does NOT hold: equal summaries do NOT imply equal content, since distinct texts can share all three counts (for example `"ab"` and `"ba"`). Tier 3 is therefore mandatory and MUST NOT be elided; an implementation that returns `true` on matching summaries alone violates this requirement.

This conformance SHALL be covered by tests in `Tests/TextRopeTests/TextRopeEqualityTests.swift` — the file established by `fix-rope-cow-and-equality-coverage`, which the summary-early-out cases extend rather than recreate. Coverage MUST NOT be claimed by a task checkbox without a rope-to-rope equality assertion existing in the suite.

#### Scenario: Two ropes with the same content are equal

- **WHEN** two `TextRope` values are constructed from the same string
- **THEN** they SHALL be equal (`==` returns `true`), pinned by `testRopesWithSameContentAreEqual`

#### Scenario: Same content over different tree shapes is equal

- **WHEN** one rope is built by a single `TextRope(_:)` construction and another rope holding identical content is assembled by incremental `insert` calls that produce a demonstrably different leaf partition
- **THEN** the two ropes SHALL be equal, pinned by `testRopesWithSameContentButDifferentTreeShapesAreEqual`, which SHALL first assert that the two leaf partitions actually differ

#### Scenario: Two ropes with different content are not equal

- **WHEN** two `TextRope` values hold different strings
- **THEN** they SHALL NOT be equal (`==` returns `false`), pinned by `testRopesWithDifferentContentAreNotEqual`

#### Scenario: Differing summaries decide inequality without materializing content

- **WHEN** two ropes differ in UTF-8 byte count, UTF-16 code unit count, or newline count
- **THEN** `==` SHALL return `false` in constant time, without building either rope's `content` string

#### Scenario: Identical UTF-16 length with differing byte count is rejected early

- **WHEN** two ropes have the same UTF-16 code unit count but different UTF-8 byte counts (for example one containing a multi-byte character where the other holds ASCII)
- **THEN** `==` SHALL return `false` via the summary early-out

#### Scenario: Same length but different content is not equal

- **WHEN** two `TextRope` values hold different strings with identical UTF-8 byte counts, UTF-16 code unit counts, and newline counts
- **THEN** they SHALL NOT be equal, pinned by `testRopesWithSameUTF16CountButDifferentContentAreNotEqual` — a summary-based early-out MUST NOT be able to satisfy this scenario by comparing summaries alone

#### Scenario: Equal summaries still require content comparison

- **WHEN** two ropes have identical `utf8`, `utf16`, and `lines` summaries but different text — the single-leaf case pinned by `testRopesWithSameUTF16CountButDifferentContentAreNotEqual`, and a multi-leaf case whose bytes are permuted across leaf boundaries
- **THEN** `==` SHALL return `false` — the early-out MUST NOT treat matching summaries as proof of equality

#### Scenario: Empty ropes are equal

- **WHEN** `TextRope()` is compared with `TextRope("")`
- **THEN** they SHALL be equal, pinned by `testEmptyRopesAreEqual`

#### Scenario: Reference-identical roots take the identity fast path

- **WHEN** a `TextRope` is copied and neither copy is mutated, so both share the same root node
- **THEN** the two values SHALL be equal without comparing summaries or content, and the shared-root precondition SHALL be asserted, pinned by `testCopyWithSharedRootIsEqual`
