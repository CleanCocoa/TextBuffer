## ADDED Requirements

### Requirement: TextRope value semantics hold under concurrent mutation

`TextRope` is `Sendable` over a `nonisolated(unsafe) var root: Node` whose element type is not `Sendable`. The safety of that declaration rests entirely on copy-on-write path-copying, so the guarantee SHALL be verified concurrently and not only single-threaded.

When a single `TextRope` value is shared with many concurrently executing tasks and each task takes its own copy and mutates it, every task SHALL observe only the effect of its own mutation, and the shared original SHALL be unchanged after all tasks complete. The verification MUST use a template whose tree has more than one level, so that `Node.ensureUniqueChild(at:)` is exercised concurrently on genuinely shared children — a single-leaf template only exercises `TextRope.ensureUnique()` at the root and proves nothing about path-copying below it.

Each task's copy MUST be taken inside the concurrently executing task body, not in the spawning loop, so that the copy and the subsequent uniqueness checks actually run in parallel against the same shared nodes.

#### Scenario: Parallel mutations from a shared multi-level rope are independent

- **WHEN** a `TextRope` whose root is an inner node of height ≥ 2 is shared with many concurrent tasks, and each task copies it and mutates at its own distinct UTF-16 offset
- **THEN** each task's result SHALL equal the result of applying only its own mutation to the template content, verified against a `String` oracle
- **AND** the template's `content` SHALL be unchanged after every task completes

#### Scenario: Concurrent buffer mutations from a multi-level template are independent

- **WHEN** a `SendableRopeBuffer` backed by a multi-leaf, multi-level rope is shared with many concurrent tasks, and each task copies it and replaces a distinct range
- **THEN** each task's buffer content SHALL reflect only its own replacement, and the shared template SHALL be unchanged

#### Scenario: Concurrency coverage is not degenerate

- **WHEN** the concurrent value-semantics tests run
- **THEN** they SHALL assert the template's tree shape (multiple leaves under multiple inner nodes) before fanning out, so that a future chunking or branching change cannot silently reduce the coverage to a single-leaf case

## MODIFIED Requirements

### Requirement: TextRope is Equatable via content comparison

`TextRope` SHALL conform to `Equatable`. Two TextRope values SHALL be equal if and only if their `content` strings are equal. Equality SHALL be independent of tree shape: two ropes holding the same characters over different leaf partitions, different child groupings, or different heights SHALL compare equal. Reference-identical roots SHALL be recognized as equal without materializing content.

This conformance SHALL be covered by tests in `Tests/TextRopeTests/TextRopeEqualityTests.swift`. Coverage MUST NOT be claimed by a task checkbox without a rope-to-rope equality assertion existing in the suite.

#### Scenario: Two ropes with the same content are equal

- **WHEN** two `TextRope` values are constructed from the same string
- **THEN** they SHALL be equal (`==` returns `true`), pinned by `testRopesWithSameContentAreEqual`

#### Scenario: Same content over different tree shapes is equal

- **WHEN** one rope is built by a single `TextRope(_:)` construction and another rope holding identical content is assembled by incremental `insert` calls that produce a demonstrably different leaf partition
- **THEN** the two ropes SHALL be equal, pinned by `testRopesWithSameContentButDifferentTreeShapesAreEqual`, which SHALL first assert that the two leaf partitions actually differ

#### Scenario: Two ropes with different content are not equal

- **WHEN** two `TextRope` values hold different strings
- **THEN** they SHALL NOT be equal (`==` returns `false`), pinned by `testRopesWithDifferentContentAreNotEqual`

#### Scenario: Same length but different content is not equal

- **WHEN** two `TextRope` values hold different strings with identical UTF-8 byte counts, UTF-16 code unit counts, and newline counts
- **THEN** they SHALL NOT be equal, pinned by `testRopesWithSameUTF16CountButDifferentContentAreNotEqual` — a summary-based early-out MUST NOT be able to satisfy this scenario by comparing summaries alone

#### Scenario: Empty ropes are equal

- **WHEN** `TextRope()` is compared with `TextRope("")`
- **THEN** they SHALL be equal, pinned by `testEmptyRopesAreEqual`

#### Scenario: Reference-identical roots take the identity fast path

- **WHEN** a `TextRope` is copied and neither copy is mutated, so both share the same root node
- **THEN** the two values SHALL be equal, and the shared-root precondition SHALL be asserted, pinned by `testCopyWithSharedRootIsEqual`
