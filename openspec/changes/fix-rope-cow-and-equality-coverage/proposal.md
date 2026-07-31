## Why

Three defects from `DEFECTS.md` (open against 0.9.1, `5cf2638`) share one root theme: `TextRope`'s copy-on-write discipline and its value-semantics contract are asserted by the specs but not actually pinned by tests, and one of them is silently broken in the delete path.

- **DEF-003 (Critical)** — `Sources/TextRope/TextRope+Delete.swift:56` binds `let child = node.children[i]`. That strong reference is still live when `node.ensureUniqueChild(at: i)` runs on line 72, so `isKnownUniquelyReferenced` never returns `true` and **every** delete path-copies the whole root-to-leaf path even when the rope has exactly one owner. This violates `openspec/specs/rope-delete/spec.md:63-65` ("Single-owner mutation avoids copying"). The guard test `testDeleteOnSingleOwnerRopeMutatesInPlace` (`Tests/TextRopeTests/TextRopeDeleteTests.swift:396-406`) passes anyway because it only checks the root (kept by `TextRope.ensureUnique()`) and `children[2]`, which is off the delete path.
- **DEF-005 (Medium)** — `TextRope: Equatable` (`Sources/TextRope/TextRope.swift:39-43`) has zero tests. The archived task `2026-07-29-m2-rope-foundation/tasks.md:36` is ticked naming Equatable coverage in `TextRopeConstructionTests.swift`, but no rope-to-rope equality assertion exists anywhere in the suite. The behavior is specified at `openspec/specs/rope-core-types/spec.md:102-113`.
- **DEF-008 (Medium)** — `SendableRopeBufferConcurrencyTests.testTaskGroupParallelReplace` fans 1000 parallel mutations out of a `"Hello, NAME!"` template, which is a single leaf. Every task's first mutation is absorbed by `TextRope.ensureUnique()` at the root; `Node.ensureUniqueChild(at:)` is never reached, so concurrent path-copying below the root is never exercised. `TextRope: Sendable` is declared over a `nonisolated(unsafe) var root: Node` where `Node` is not `Sendable` — the safety of that declaration rests entirely on the COW discipline this test is supposed to verify.

DEF-003 is a live performance defect (every single-owner delete allocates a full path of nodes). DEF-005 and DEF-008 are coverage gaps that let DEF-003-class regressions ship unnoticed.

## What Changes

**DEF-003 — single-owner delete pessimization**

- Strengthen `testDeleteOnSingleOwnerRopeMutatesInPlace` to assert reference identity of the **on-path** child and leaf, not only the root and an off-path sibling. This test fails on HEAD.
- Add a multi-level (height 2) single-owner identity test so the guarantee is pinned at more than one tree depth.
- Fix `TextRope+Delete.swift:56` — read the scalar `node.children[i].summary.utf16` instead of binding the child node, so no alias outlives the `ensureUniqueChild(at: i)` call for that index.
- Audit the insert and replace descents for the same alias pattern and record the finding in `design.md`; add single-owner identity regression tests for `insert` and `replace` that pin the existing (already-correct) `rope-insert/spec.md:48-50` and `rope-replace/spec.md:88-90` scenarios.

**DEF-005 — missing `TextRope: Equatable` coverage**

- Add `Tests/TextRopeTests/TextRopeEqualityTests.swift` covering: equal content across **differing tree shapes** (a rope built by construction vs. the same content assembled by incremental inserts), unequal content, equal-length-but-different content (a guard for any future summary-based early-out per DEF-010), empty ropes, and the `lhs.root === rhs.root` identity fast path.

**DEF-008 — no concurrent-COW test on multi-level ropes**

- Add a concurrent value-semantics test driven from a **multi-leaf, height-2** template so every task's mutation descends through shared inner nodes and shared leaves, forcing concurrent `ensureUniqueChild(at:)` on genuinely shared children — at the `TextRope` level and at the `SendableRopeBuffer` level.
- Record a ThreadSanitizer design note (invocation, task/tree sizing, why the copy must be taken inside the child task) in `design.md`. TSan is not wired into CI by this change.

No production behavior other than the DEF-003 allocation fix changes; no public API changes.

## Capabilities

### New Capabilities
<!-- None — all affected capabilities already have canonical specs. -->

### Modified Capabilities
- `rope-delete`: "COW path-copying on delete" gains a normative no-aliasing rule for the descent and replaces the untestable "modifies nodes in place without allocating new node objects" scenario with on-path reference-identity scenarios, plus an explicit carve-out for deletes that trigger merge/redistribution.
- `rope-core-types`: "TextRope is Equatable via content comparison" gains scenarios pinned to named tests (differing tree shapes, equal length with different content, identity fast path); a new requirement is ADDED for value semantics under concurrent mutation of a shared multi-level rope.

## Impact

- **Sources/TextRope/TextRope+Delete.swift** — one-line change in `deleteFromInner` (line 56); no signature or behavior change beyond allocation avoidance.
- **Tests/TextRopeTests/TextRopeDeleteTests.swift** — `testDeleteOnSingleOwnerRopeMutatesInPlace` strengthened; new multi-level single-owner identity test.
- **Tests/TextRopeTests/TextRopeInsertTests.swift**, **TextRopeReplaceTests.swift** — new single-owner identity regression tests.
- **Tests/TextRopeTests/TextRopeEqualityTests.swift** — new file.
- **Tests/TextRopeTests/TextRopeConcurrentCOWTests.swift** — new file.
- **Tests/TextBufferTests/SendableRopeBufferConcurrencyTests.swift** — new multi-level parallel-mutation test.
- **DEFECTS.md** — DEF-003, DEF-005, DEF-008 move to `fixed`.
- **CHANGELOG.md** — one `Fixed` entry (DEF-003) and one `Changed` entry (coverage) under the upcoming patch release.
- **No API changes, no new dependencies, no changes to `Package.swift`.**
- **Explicitly out of scope:** DEF-001, DEF-002, DEF-004, DEF-006, DEF-007, DEF-009 through DEF-014. In particular this change does **not** implement DEF-010's summary-based `==` early-out; it only adds the equal-length/different-content test that such an optimization would have to keep green.
- **Coordination:** the parallel change `perf-rope-equality-and-bulk-insert` (DEF-010/DEF-011) modifies the same `rope-core-types` requirement, "TextRope is Equatable via content comparison". The two deltas are behaviorally compatible but overlap textually — see `design.md` → Open Questions for the proposed merge resolution and the required archive ordering.
