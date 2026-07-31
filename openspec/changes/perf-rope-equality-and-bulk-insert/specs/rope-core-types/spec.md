## MODIFIED Requirements

### Requirement: TextRope is Equatable via content comparison
`TextRope` SHALL conform to `Equatable`. Two TextRope values SHALL be equal if and only if their `content` strings are equal.

Equality SHALL be decided in three tiers, in order:

1. **Identity.** If both values share the same root node (`lhs.root === rhs.root`), they SHALL be equal without further work.
2. **Summary early-out.** Otherwise, if the two root summaries differ in any field (`utf8`, `utf16`, or `lines`), the values SHALL be unequal. This comparison MUST be O(1) and MUST NOT materialize either rope's content.
3. **Content comparison.** Otherwise, equality SHALL be decided by comparing the materialized `content` strings.

Tier 2 is sound because every `Summary` field is a pure, additive function of the text: `utf8` is its UTF-8 byte count, `utf16` its UTF-16 code unit count, and `lines` its `\n` count. A node's summary equals the sum over its subtree, so the root summary equals that same function applied to `content`. Equal content therefore implies equal summaries, and — by contraposition — differing summaries prove differing content.

The converse does NOT hold: equal summaries do NOT imply equal content, since distinct texts can share all three counts (for example `"ab"` and `"ba"`). Tier 3 is therefore mandatory and MUST NOT be elided; an implementation that returns `true` on matching summaries alone violates this requirement.

Equality MUST NOT depend on tree shape. Two ropes holding identical text SHALL be equal regardless of leaf chunk boundaries, node count, or tree height — no term of the comparison may be shape-derived.

#### Scenario: Two ropes with the same content are equal
- **WHEN** two `TextRope` values are constructed from the same string
- **THEN** they SHALL be equal (`==` returns `true`)

#### Scenario: Two ropes with different content are not equal
- **WHEN** two `TextRope` values hold different strings
- **THEN** they SHALL NOT be equal (`==` returns `false`)

#### Scenario: Differing summaries decide inequality without materializing content
- **WHEN** two ropes differ in UTF-8 byte count, UTF-16 code unit count, or newline count
- **THEN** `==` SHALL return `false` in constant time, without building either rope's `content` string

#### Scenario: Equal summaries still require content comparison
- **WHEN** two ropes have identical `utf8`, `utf16`, and `lines` summaries but different text (for example `"ab"` and `"ba"`)
- **THEN** `==` SHALL return `false` — the early-out MUST NOT treat matching summaries as proof of equality

#### Scenario: Equal content with different tree shapes compares equal
- **WHEN** one rope is constructed directly from a string and another reaches the same string through a sequence of `insert` and `delete` operations, producing different leaf chunk boundaries
- **THEN** the two ropes SHALL be equal

#### Scenario: Identical UTF-16 length with differing byte count is rejected early
- **WHEN** two ropes have the same UTF-16 code unit count but different UTF-8 byte counts (for example one containing a multi-byte character where the other holds ASCII)
- **THEN** `==` SHALL return `false` via the summary early-out

#### Scenario: A rope equals its own unmutated copy
- **WHEN** a `TextRope` is copied and neither copy is mutated
- **THEN** `==` SHALL return `true` via the shared-root identity check, without comparing summaries or content
