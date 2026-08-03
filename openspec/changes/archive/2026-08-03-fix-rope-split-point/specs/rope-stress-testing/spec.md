## MODIFIED Requirements

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
