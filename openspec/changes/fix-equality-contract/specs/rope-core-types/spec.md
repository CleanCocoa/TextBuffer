## MODIFIED Requirements

### Requirement: TextRope is Equatable via content comparison

> Rebased on the `fix-rope-cow-and-equality-coverage` delta for this requirement, which lands first. This version carries that delta's text forward and adds the tiered summary early-out; it does not replace its coverage obligations.
>
> Amended by `fix-equality-contract` (DEF-018): the equality dialect is stated explicitly as **code-unit** (UTF-8) equality. The previous wording — "their `content` strings are equal" — read as Swift `String ==`, i.e. Unicode canonical equivalence, which contradicted the tier-2 soundness proof below; that proof is valid only under code-unit semantics. The tier structure is unchanged.

`TextRope` SHALL conform to `Equatable`. Two TextRope values SHALL be equal if and only if their contents are the same sequence of UTF-8 code units.

This is **code-unit equality**, deliberately different from Swift's `String ==`, which decides by Unicode canonical equivalence. Two contents that a user would see rendered identically SHALL NOT be equal unless their code units agree: `TextRope("é")` (U+00E9) and `TextRope("e\u{301}")` (U+0065 U+0301) SHALL NOT be equal, and neither SHALL two ropes whose combining marks differ only in canonical order. The reason is congruence over the offset-addressed API: `a == b` MUST imply that `a` and `b` answer every count query identically and behave identically under the same operation at the same UTF-16 offset. Canonically equivalent contents can differ in `utf16Count`, so canonical equality would not be a congruence and would let consumers treat divergent documents as the same.

Equality SHALL be independent of tree shape: two ropes holding the same code units over different leaf partitions, different child groupings, or different heights SHALL compare equal — no term of the comparison may be shape-derived.

Equality SHALL be decided in three tiers, in order:

1. **Identity.** If both values share the same root node (`lhs.root === rhs.root`), they SHALL be equal without further work.
2. **Summary early-out.** Otherwise, if the two root summaries differ in any field (`utf8`, `utf16`, or `lines`), the values SHALL be unequal. This comparison MUST be O(1) and MUST NOT materialize either rope's content.
3. **Code-unit comparison.** Otherwise, equality SHALL be decided by comparing the two contents code unit by code unit — `true` only when the two UTF-8 sequences have the same length and agree at every position. Whether the implementation materializes both contents or streams them leaf by leaf is an implementation choice; every implementation MUST decide identically.

Tier 2 is sound because every `Summary` field is a pure, additive function of the text's code units: `utf8` is its UTF-8 byte count, `utf16` its UTF-16 code unit count, and `lines` its `\n` count. A node's summary equals the sum over its subtree, so the root summary equals that same function applied to `content`. Equal content therefore implies equal summaries, and — by contraposition — differing summaries prove differing content.

That proof holds **only** for code-unit equality at tier 3. Under canonical equivalence the required implication is false — `"é"` and `"e\u{301}"` are canonically equal while differing in `utf8` and `utf16` — so a canonical tier 3 would make the early-out unsound, returning `false` for a pair the contract calls equal. A tier-3 relation that is not code-unit equality therefore invalidates tier 2 and MUST NOT be introduced without removing it.

The converse does NOT hold: equal summaries do NOT imply equal content, since distinct texts can share all three counts (for example `"ab"` and `"ba"`, or two combining-mark runs differing only in canonical order). Tier 3 is therefore mandatory and MUST NOT be elided; an implementation that returns `true` on matching summaries alone violates this requirement.

`TextRope` SHALL additionally provide two named predicates, both implementable with the Swift standard library alone so the TextRope target stays Foundation-free per ADR-013:

- `isCanonicallyEquivalent(to:) -> Bool` SHALL answer the render-equality question: `true` exactly when the two contents are equal under Swift `String ==` (Unicode canonical equivalence). `==` SHALL imply `isCanonicallyEquivalent(to:)`; the converse SHALL NOT hold. Documentation SHALL route callers explicitly — use this predicate for render-equality questions, `==` for byte fidelity.
- `isTriviallyIdentical(to:) -> Bool` SHALL expose tier 1: `true` exactly when the two values share the same root node. It SHALL be O(1) and MUST NOT read summaries or materialize content. Its contract is one-directional: `true` SHALL imply `==`, while `false` SHALL imply nothing — two ropes holding identical code units MAY report `false` once copy-on-write has given them separate roots.

`TextRope` SHALL NOT conform to `Hashable` under this requirement. Should a future change add that conformance, `hash(into:)` MUST be computed over exactly the UTF-8 code units that `==` compares — no normalization, no shape-derived term — so that every pair this requirement calls equal hashes equally.

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

#### Scenario: Canonically equivalent NFC and NFD content is not equal

- **WHEN** `TextRope("é")` (U+00E9) is compared with `TextRope("e\u{301}")` (U+0065 U+0301), whose contents Swift `String ==` reports as equal
- **THEN** `==` SHALL return `false`, decided by the summary early-out — the two differ in both `utf8` and `utf16`

#### Scenario: Canonically reordered combining marks are not equal despite identical summaries

- **WHEN** `TextRope("e\u{301}\u{323}")` is compared with `TextRope("e\u{323}\u{301}")` — the same three scalars in different canonical order, so `utf8`, `utf16`, and `lines` are pairwise identical and Swift `String ==` reports the two contents as equal
- **THEN** the identical summaries SHALL be asserted first, and `==` SHALL return `false`, decided at tier 3 by code-unit comparison
- **AND** `MutableStringBuffer` holding the same two contents SHALL likewise report them unequal, so the two `Buffer` conformers agree

#### Scenario: Canonical equivalence is answered by isCanonicallyEquivalent(to:)

- **WHEN** either canonically equivalent pair above is compared with `isCanonicallyEquivalent(to:)`
- **THEN** the result SHALL be `true` while `==` on the same pair SHALL be `false`
- **AND** two ropes holding identical code units SHALL report `true` from both, and two ropes holding neither code-unit-equal nor canonically equivalent content SHALL report `false` from both

#### Scenario: Trivial identity holds for copies that share a root

- **WHEN** a `TextRope` is copied and neither copy is mutated
- **THEN** `isTriviallyIdentical(to:)` SHALL return `true` without reading summaries or content, and `==` SHALL also return `true`

#### Scenario: Trivial identity is one-directional after copy-on-write divergence

- **WHEN** a copy is mutated and then restored so that it holds exactly the original's code units over a separately rooted tree
- **THEN** `isTriviallyIdentical(to:)` SHALL return `false` while `==` SHALL return `true` — a `false` result SHALL NOT be read as inequality

#### Scenario: A future Hashable conformance hashes exactly the compared code units

- **WHEN** a future change adds `Hashable` to `TextRope`
- **THEN** `hash(into:)` SHALL feed exactly the UTF-8 code units that `==` compares, so every pair this requirement calls equal hashes equally; hashing normalized text, or any shape-derived term, SHALL be a violation
- **AND** until such a change lands, `TextRope` SHALL NOT conform to `Hashable`

## ADDED Requirements

### Requirement: TextRope never normalizes and normalization is a caller-boundary policy

`TextRope` SHALL store exactly the UTF-8 code units it is given. No operation — construction from a `String`, `insert`, `delete`, `replace`, `content` materialization, or any read — SHALL apply Unicode normalization (NFC, NFD, NFKC, NFKD), canonical reordering, or any other code-unit-altering transformation to the text. A rope's `content` SHALL be byte-identical to the concatenation of everything inserted into it minus what was deleted, and the package SHALL NOT provide a normalizing entry point.

Consequently mixed encodings coexist in one document without reconciliation, and code-unit-different inputs are different documents even when canonically equivalent: applying the same edit script to two such ropes MAY yield different content and different `utf16Count`, and the implementation SHALL NOT attempt to bring them together.

Normalization is a **caller-boundary policy**. The package takes no position on whether an application should normalize; it takes the position that if an application does, it does so before the text reaches a rope. Callers SHALL be routed by the question they are actually asking:

- **Render-equality** ("would these two show the same glyphs?") → `isCanonicallyEquivalent(to:)`. Normalizing the stored text SHALL NOT be recommended as the way to answer this.
- **Uniform storage** ("every document I hold should be NFC") → normalize at ingress, in the application, e.g. via Foundation's `precomposedStringWithCanonicalMapping`, before constructing or inserting into a rope.
- **Range derivation over composed text** ("what is the whole character at this offset?") → the existing composed-sequence, word, and line expansion APIs. Normalization SHALL NOT be presented as a range primitive.

Wherever the ingress route is recommended, the guidance MUST name its caveat: NFC is not encoding-only. It singleton-decomposes the CJK compatibility ideographs (U+F900–U+FAFF — for example `U+F900` normalizes to `U+8C48`), so blanket ingress normalization changes characters rather than only re-encoding them, and a document round-tripped through it is not the document the user supplied.

#### Scenario: Inserting NFD content leaves the bytes NFD

- **WHEN** `insert("e\u{301}", at:)` places a decomposed `é` into a rope
- **THEN** `content` SHALL contain U+0065 followed by U+0301 — the scalars SHALL NOT be composed to U+00E9 — and `utf8Count` and `utf16Count` SHALL reflect the decomposed form

#### Scenario: Constructing from precomposed content leaves the bytes precomposed

- **WHEN** `TextRope("é")` is constructed from U+00E9
- **THEN** `content` SHALL be U+00E9 — the scalar SHALL NOT be decomposed — and `utf8Count` SHALL be 2 with `utf16Count` 1

#### Scenario: Mixed encodings coexist in one document across mutations

- **WHEN** a document holds a precomposed `é` and a decomposed `e\u{301}` at different offsets and is edited by `insert`, `delete`, and `replace` adjacent to each
- **THEN** every code unit of both forms SHALL survive unchanged, and a read over each range SHALL return the form stored there

#### Scenario: Canonical equivalence never leaks into a mutation's result

- **WHEN** the same edit script is applied to two ropes whose contents are canonically equivalent but code-unit different
- **THEN** the two results MAY differ in `content` and in `utf16Count`, and neither rope SHALL have normalized toward the other

#### Scenario: Ingress normalization guidance names the CJK compatibility caveat

- **WHEN** documentation or spec guidance recommends normalizing at the caller boundary
- **THEN** it SHALL identify the step as application-level and Foundation-side (`precomposedStringWithCanonicalMapping`), and SHALL state that NFC singleton-decomposes CJK compatibility ideographs (U+F900–U+FAFF, e.g. `U+F900` → `U+8C48`), so blanket ingress normalization is a policy choice that changes characters and not merely their encoding
