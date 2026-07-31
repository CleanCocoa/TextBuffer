## Context

`TextRope` is a B-tree rope with copy-on-write path-copying (ADR-005, ADR-006, ADR-007). Its `Sendable` conformance is declared over `nonisolated(unsafe) var root: Node` where `Node` is a non-`Sendable` `final class` (`Sources/TextRope/TextRope.swift:12-13`) — the value-type wrapper plus the COW discipline is the entire safety argument.

That discipline has one mechanical requirement: at the moment `isKnownUniquelyReferenced` runs on a node, no other strong reference to that node may be live. `Node.ensureUniqueChild(at:)` (`Sources/TextRope/Node.swift:59-63`) checks the array element in place, which is correct — but only if the *caller's* descent has not already bound the same child to a local.

The delete descent breaks exactly that rule:

```swift
for i in 0..<node.children.count {
    let child = node.children[i]          // TextRope+Delete.swift:56 — alias, live until :78
    ...
    node.ensureUniqueChild(at: i)         // :72 — always sees refcount >= 2
    if deleteFromNode(node.children[i], ...) { ... }
}
```

The insert descent, for contrast, already reads only a scalar:

```swift
let childUTF16 = node.children[i].summary.utf16   // TextRope+Insert.swift:30
if remaining < childUTF16 || i == node.children.count - 1 {
    node.ensureUniqueChild(at: i)                 // :32
```

The existing guard test cannot catch this, because it samples the root (which `TextRope.ensureUnique()` keeps for a single owner regardless) and `children[2]`, which the delete at offset 100 never touches.

This change is scoped to DEF-003, DEF-005, and DEF-008 from `DEFECTS.md`. It corresponds to no roadmap task in `TASKS.md`; it is defect remediation against 0.9.1.

## Goals / Non-Goals

**Goals:**

- Make the single-owner delete actually mutate in place, and make that fact observable by test.
- Give `TextRope: Equatable` the test coverage its canonical spec already mandates.
- Exercise concurrent path-copying below the root, where `ensureUniqueChild(at:)` is the contended operation.
- Leave behind test names that the canonical specs can point at, so the next audit can verify coverage by grep.

**Non-Goals:**

- DEF-001 (`balancedSplitPoint` fallback), DEF-002 (regional-indicator pairing), DEF-004 (empty-range preconditions), DEF-006 (spec contradictions), DEF-007 (stress sampling rate), DEF-009 (`expandingWindow` length assumption), DEF-011 through DEF-014.
- DEF-010's summary-based `==` early-out. This change only adds the equal-length/different-content case that such an optimization must keep green.
- Wiring ThreadSanitizer into CI.
- Any change to `Node`, `Summary`, `TextRope+COW.swift`, or the public API.
- Reworking the merge/redistribute allocation behavior in `mergeUndersizedLeaves` / `mergeUndersizedInnerNodes`.

## Decisions

### D1: Fix the alias by reading the scalar, not the node

In `deleteFromInner`, `child` is used only for `child.summary.utf16` (lines 57 and 69). Replace the binding with `let childUTF16 = node.children[i].summary.utf16` and use `childUTF16` at both sites. This matches the shape the insert descent already uses, so the two descents read alike.

Alternatives rejected:

- *Scope the binding tighter with a `do { }` block* — brittle; a later edit re-widens it silently.
- *Pass the child index down instead of the node* — a larger refactor of `deleteFromNode`'s signature with no additional benefit.
- *Make `ensureUniqueChild` take an expected refcount* — `isKnownUniquelyReferenced` has no such API, and it would encode the bug as a contract.

### D2: Identity must be captured non-owningly, or the test defeats itself

A test that writes `let before = rope.root.children[0]` and compares with `===` after the delete would **fail even after the fix**: the `before` binding is itself the second strong reference, so `ensureUniqueChild` correctly copies. Identity must be captured as `ObjectIdentifier(rope.root.children[0])`, which holds no ownership — the pattern the existing `testDeleteOnSingleOwnerRopeMutatesInPlace` already uses and the reason it must be preserved when strengthening the test.

Residual hazard: a stale `ObjectIdentifier` can collide with a later allocation at the same address, which would read as a false pass. `ensureUniqueChild` allocates the `shallowCopy()` before releasing the original (`children[index] = children[index].shallowCopy()`), so the two are never co-located; and the shared-rope counterpart `testDeleteOnSharedRopeSharesUnaffectedSubtrees` acts as the positive control that identity *does* change when it should. Every identity test also asserts content, so a false pass on identity cannot mask a correctness regression.

### D3: The in-place guarantee is scoped to deletes that do not rebalance

`openspec/specs/rope-delete/spec.md:63-65` currently promises "no new node objects along the path" unconditionally. That is not achievable and never was: `mergeUndersizedLeaves` builds replacement leaves via `Node.leaf(combined)` and `combinedInner` builds replacement inner nodes via `Node.inner(children)` whenever a delete pushes a node under its minimum. Those allocations are inherent to B-tree rebalancing, not a COW miss.

The spec delta therefore replaces the unbounded promise with two scenarios: on-path reference identity for deletes that stay within size bounds, and an explicit carve-out acknowledging that rebalancing deletes may allocate replacement nodes. The tests use a 10-unit delete from a 2048-byte leaf, which is comfortably inside the bound.

### D4: Insert/replace audit — no second occurrence; regression guards only

Full audit of every `ensureUniqueChild(at:)` call site and its enclosing scope:

| Site | Enclosing binding | Verdict |
| --- | --- | --- |
| `TextRope+Delete.swift:72` | `let child = node.children[i]` (`:56`), live through `:78` | **Defect (DEF-003)** |
| `TextRope+Insert.swift:32` | `let childUTF16 = node.children[i].summary.utf16` (`:30`) — scalar only | Clean |
| `TextRope+Insert.swift:48` | preceded by `crlfSeam(between: node.children[i - 1], and: node.children[i])` (`:47`); argument temporaries die at the end of that call | Clean |
| `TextRope+Insert.swift:94` (`rightmostSpine`) | `spine`/`current` hold the *parent*; the node under check is `current.children[last]`, unaliased at check time | Clean |
| `TextRope+Insert.swift:105` (`leftmostSpine`) | same shape as `rightmostSpine` | Clean |

Two further findings, both benign:

- `deleteFromInner`'s whole-child-removal branch (`:69-70`) deliberately does not call `ensureUniqueChild` — the child is removed from the parent's array, never mutated, and the parent is already unique. Correct as written.
- `mergeUndersizedLeaves` (`:128`) and `mergeUndersizedInnerNodes` (`:166`) do bind `var current = node.children[i]`, but they never call `ensureUniqueChild`; they construct fresh nodes. See D3.

`replace` (`TextRope+Replace.swift:9-10`) is `delete` then `insert` with no descent of its own, so it inherits both paths.

Consequence: `rope-insert` and `rope-replace` need **no spec change**. Their single-owner scenarios (`rope-insert/spec.md:48-50`, `rope-replace/spec.md:88-90`) are correct but untested; this change adds tests that pin them, so the next audit finds coverage rather than a claim.

### D5: Equatable tests get their own file and force tree-shape divergence

New file `Tests/TextRopeTests/TextRopeEqualityTests.swift` rather than appending to `TextRopeConstructionTests.swift`. Equality is not a construction concern, and a dedicated file makes the coverage claim in `2026-07-29-m2-rope-foundation/tasks.md:36` verifiable by file name.

The "same content, different tree shape" case is the one that actually exercises `==`'s content path: build rope A from a >4 KB string in one `TextRope(_:)` call, and rope B by starting from a prefix and applying incremental `insert` calls that drive splits at different offsets. The two ropes then hold identical content over demonstrably different leaf partitions — assert the partitions differ (`root.height` or the leaf-chunk length vector) before asserting `A == B`, otherwise the test silently degrades into the trivial case.

The identity fast-path case (`lhs.root === rhs.root`, `TextRope.swift:41`) is asserted structurally: `let b = a` gives `a.root === b.root`, and `a == b` must hold. `@testable import TextRope` already gives the tests access to `root`.

### D6: Concurrent-COW test design and the ThreadSanitizer note

**Template shape.** Use 20 blocks of 2048 identical bytes (`(0..<20).map { String(repeating: ..., count: 2048) }.joined()`), the same shape `testDeleteOnSharedRopeSharesUnaffectedSubtrees` already relies on: root → 3 inner children with `[8, 8, 4]` leaves, height 2. Assert that shape at the top of the test so a future chunking change fails loudly instead of silently reverting the test to a single-leaf case.

**Fan-out.** ~64 concurrent tasks, each mutating at a *different* offset so the tasks spread across different inner children and leaves while all descending from the same shared root. Each task compares its own result against a `String` oracle; after the group drains, assert the template is byte-identical to its original content.

**The copy must be taken inside the child task.** `testTaskGroupParallelReplace` binds `var buffer = template` in the parent loop (`:14`) and mutates it inside the task, so the copy — and therefore part of the retain traffic on the shared root — is serialized on the parent. The new tests take `var local = template` as the first statement *inside* `group.addTask`, so `ensureUnique()` and `ensureUniqueChild(at:)` genuinely run concurrently against the same shared nodes.

**Two levels of test.** One at `TextRope` level (`Tests/TextRopeTests/TextRopeConcurrentCOWTests.swift`) — that is the type whose `Sendable` conformance is at stake — and one at `SendableRopeBuffer` level in the existing `SendableRopeBufferConcurrencyTests.swift`, since DEF-008 names that file and the buffer adds an `OperationLog` per copy.

**TSan viability.**

- Invocation: `swift test --sanitize=thread --filter TextRopeConcurrentCOWTests` and `swift test --sanitize=thread --filter SendableRopeBufferConcurrencyTests`.
- Sizing is chosen for TSan, not for throughput. TSan's shadow memory and instrumentation cost roughly an order of magnitude in time and several times in RSS; 64 tasks over a 40 KB template keeps a sanitized run in seconds, where the existing 1000-task fan-out would not. Race detection depends on contention shape, not on iteration count — 64 tasks contending on the same three inner nodes is a better detector than 1000 tasks that each touch one leaf.
- The test class must stay un-isolated (no `@MainActor`). XCTest's `async` test methods run on the cooperative pool; a `@MainActor`-isolated class would serialize every task and TSan would observe no concurrency at all. `SendableRopeBufferConcurrencyTests` is un-annotated today — keep it that way.
- Pool width is `activeProcessorCount`; on a single-core runner the tasks can serialize and TSan will find nothing. The TSan run is therefore a documented developer-local gate recorded in the tests' doc comments, not a CI gate. Wiring CI is out of scope (see Open Questions).
- Expected failure signature if the COW discipline breaks: a TSan report on `TextRope.Node.chunk`, `.children`, or `.summary`, or on `swift_retain`/`swift_release` for a shared node. Without TSan, the same breakage surfaces as content corruption in the per-task oracle assertion — both are asserted, so the tests are meaningful in an unsanitized run too.

### D7: Red-first sequencing

Only DEF-003 has a behavior defect, so only its tests can be genuinely red. Task group 1 lands the two failing identity tests and records their failure output *before* group 2 touches `TextRope+Delete.swift`; group 2 then re-runs them to green.

The DEF-005 and DEF-008 tasks are coverage, not remediation: those tests are expected to pass on HEAD. That expectation is written into the tasks — if any of them fails on HEAD, it is a newly discovered defect and must be filed in `DEFECTS.md` rather than fixed inline under this change.

## Risks / Trade-offs

- **[Structure-coupled assertions]** → The identity and concurrency tests hard-code a tree shape derived from `maxChunkUTF8 = 2048` / `maxChildren = 8`. Tuning those constants (flagged as likely in the m2-rope-foundation design) breaks these tests for reasons unrelated to COW. Mitigation: every such test asserts the expected shape up front with an explanatory message, exactly as `testDeleteOnSharedRopeSharesUnaffectedSubtrees` does with `[8, 8, 4]`, so a shape change fails with a diagnosis rather than a mystery.
- **[Address-reuse false pass]** → Covered in D2; mitigated by allocation ordering inside `ensureUniqueChild`, by the shared-rope positive control, and by pairing every identity assertion with a content assertion.
- **[Concurrency tests are probabilistic]** → A COW race is a race; a green unsanitized run proves less than it appears to. This is why the TSan invocation is documented in the test doc comments and why the tests also assert per-task content against an oracle, which is deterministic.
- **[Fixing DEF-003 changes allocation behavior in the stress suite]** → Fewer nodes are allocated per delete after the fix, so any stress test that (inadvertently) depends on path-copying identity could shift. `TextRopeStressTests` compares against a `String` oracle and validates invariants, neither of which is identity-sensitive; expected to be unaffected, but the full suite run in the verification group is the check.
- **[DEF-010 remains open]** → `==` still materializes both ropes on mismatch. This change makes that path *tested*, which arguably makes it harder to change later. Mitigation: the equal-length/different-content scenario is written specifically so a summary-based early-out cannot pass it by accident.

## Open Questions

- **Spec collision with `perf-rope-equality-and-bulk-insert` (DEF-010), which is active in parallel.** That change MODIFIES the same requirement — `rope-core-types` → "TextRope is Equatable via content comparison" — replacing its text with a three-tier contract (identity → summary early-out → content). The two deltas are behaviorally compatible (this change's "same length but different content" scenario is precisely the guard that DEF-010's tier 2 must not break), but they cannot both be merged verbatim: whichever archives second overwrites the other's requirement paragraph. Proposed resolution — DEF-010 owns the requirement *text*, this change owns the *coverage obligation* sentence and the test-name pins; at merge time fold this change's scenarios into DEF-010's tiering text, and collapse this change's "Same length but different content is not equal" with DEF-010's "Equal summaries still require content comparison" into a single scenario that carries the test name. Confirm the merge order before archiving either.
- **Should DEF-010's summary-based early-out land in the same release?** The new Equatable tests are the natural guard for it and the two defects touch the same six lines of `TextRope.swift`. Splitting them means touching `TextRope.swift:39-43` twice; folding them in widens this change from "coverage + one-line fix" to a behavior change. Currently proposed as **deferred to `perf-rope-equality-and-bulk-insert`** — but see the collision item above.
- **Should the TSan run be a CI gate?** No sanitizer invocation exists anywhere in the repo today, and the cooperative pool's width on the runner determines whether the test detects anything at all. Deferred, but if TSan is never run the concurrent tests degrade to oracle checks.
- **The archived task `2026-07-29-m2-rope-foundation/tasks.md:36` is ticked for coverage that was never written.** Archived changes are treated as immutable history in this repo, so the correction is recorded here rather than by editing the archive. Confirm that is the preferred convention, or amend the archive with a review-fold note the way task 4.2 of that same file was amended.
- **Should the delete descent gain a debug-only assertion** (e.g. `assert(isKnownUniquelyReferenced(&child))` behind `#if DEBUG`) so an alias regression trips at run time rather than only in the identity tests? It would need a mutable binding of its own and so would perturb the thing it measures. Not proposed; raised because identity tests alone are a shape-sensitive guard.
- **Is a 20-leaf / height-2 template deep enough for DEF-008?** It exercises two levels of `ensureUniqueChild` below the root. A height-3 template (72 blocks, ~144 KB, as `testSummaryStaysCorrectAfterMultiLevelCascadingMerges` uses) exercises three but costs ~3.5× the memory per concurrent copy under TSan. Proposed as height 2; escalate if TSan finds nothing and the deeper shape is cheap enough in practice.
