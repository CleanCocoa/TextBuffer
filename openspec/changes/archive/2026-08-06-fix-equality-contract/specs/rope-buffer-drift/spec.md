## ADDED Requirements

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
