## MODIFIED Requirements

### Requirement: Tree structure validation under stress
The stress test MUST validate the internal tree structure of the rope. Validation SHALL confirm: every inner node's summary equals the sum of its children's summaries, every leaf's summary equals `Summary.of(chunk)`, tree height is consistent (all leaves at the same depth), no `\r\n` pair is split across chunk boundaries, and every leaf's chunk size satisfies the asymmetric chunk-size bounds — at most `maxChunkUTF8`, and at least `minChunkUTF8` unless the documented carve-out (no adjacent sibling can absorb it and the combined slice has no `Character` boundary in its legal window) provably applies.

At least one seeded run MUST validate the full tree structure after **every** operation, not on a sampled interval. Sampled validation MAY be used for the remaining runs to keep suite runtime bounded, but MUST NOT be the only validation performed by the suite: structural violations produced by redistribution are transient and are repaired or masked by subsequent operations, so a 1-in-100 sample can miss them indefinitely. Validation MUST also occur at the end of every stress run. A validation failure MUST report the seed and the zero-based operation index.

#### Scenario: Per-operation validation on at least one seed
- **WHEN** the stress suite runs
- **THEN** at least one seeded run SHALL call full tree-invariant validation after every single operation, and its failures SHALL name the seed and operation index

#### Scenario: A transient oversized leaf fails at the operation that caused it
- **WHEN** an operation leaves a leaf larger than `maxChunkUTF8` and a later operation would repair or hide it
- **THEN** the per-operation run SHALL fail at the causing operation rather than at a later sampled checkpoint or not at all

#### Scenario: Undersized leaves are judged against the carve-out, not skipped
- **WHEN** validation encounters a leaf below `minChunkUTF8` in a rope whose root is an inner node
- **THEN** it SHALL fail unless every adjacent sibling both exceeds the merge capacity and shares no `Character` boundary inside the legal redistribution window

#### Scenario: Tree structure is valid after 10K operations
- **WHEN** 10,000 random operations complete
- **THEN** a full tree traversal confirms summary consistency at every node, uniform leaf depth, chunk sizes within the asymmetric bounds, and no `\r\n` splits across chunk boundaries

#### Scenario: Periodic validation during sampled stress runs
- **WHEN** a stress run uses sampled validation
- **THEN** tree structure validation occurs at regular intervals (e.g. every 100 operations) in addition to the final validation
