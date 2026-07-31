## 1. Red: pin the single-owner delete guarantee (DEF-003)

These tasks land failing tests only. Do not touch `Sources/TextRope/` in this group.

- [ ] 1.1 Strengthen `testDeleteOnSingleOwnerRopeMutatesInPlace` in `Tests/TextRopeTests/TextRopeDeleteTests.swift:396-406`: keep the existing root and off-path `children[2]` assertions, and add an assertion on the **on-path** child — for `delete(in: NSRange(location: 100, length: 10))` on the 4×2048-byte template that is `root.children[0]`. Capture identity as `ObjectIdentifier(rope.root.children[0])` **before** the delete; never bind the node itself to a `let` (a node binding is a second strong reference and would make the test fail even after the fix — design D2). Add a `rope.content` assertion alongside. **Expected: RED on HEAD.**
- [ ] 1.2 Add `testDeleteOnSingleOwnerMultiLevelRopeKeepsOnPathNodeIdentity` to the same file, using the 20×2048-byte template from `testDeleteOnSharedRopeSharesUnaffectedSubtrees`. Assert the tree shape (`root.children.map(\.children.count) == [8, 8, 4]`, height 2) up front with an explanatory message, capture `ObjectIdentifier` for `root`, `root.children[0]`, and `root.children[0].children[0]`, run `delete(in: NSRange(location: 100, length: 10))`, then assert all three are unchanged and that `content` is correct. **Expected: RED on HEAD.**
- [ ] 1.3 Run `swift test --filter TextRopeDeleteTests` and record the failing output for 1.1 and 1.2 in the commit message. Both must fail on the on-path identity assertion specifically (not on content, not on the root). Do not start group 2 until that is observed.
- [ ] 1.4 Confirm `testDeleteOnSingleOwnerRopeMutatesInPlace`'s sibling `testDeleteOnSharedRopeSharesUnaffectedSubtrees` (`:408-430`) still passes untouched — it is the positive control proving path-copying *does* occur when the rope is shared, and it must stay green through group 2.

## 2. Green: remove the alias and audit the other descents (DEF-003)

- [ ] 2.1 In `Sources/TextRope/TextRope+Delete.swift:56`, replace `let child = node.children[i]` with `let childUTF16 = node.children[i].summary.utf16`, and use `childUTF16` at both consumers — `childEnd` (`:57`) and the whole-child-removal test (`:69`). No other line in `deleteFromInner` may hold a `Node` binding that is live at the `node.ensureUniqueChild(at: i)` call on `:72`.
- [ ] 2.2 Re-run `swift test --filter TextRopeDeleteTests` — 1.1 and 1.2 must now pass, 1.4's control must still pass.
- [ ] 2.3 Walk every `ensureUniqueChild(at:)` call site against the audit table in `design.md` D4 (`TextRope+Delete.swift:72`; `TextRope+Insert.swift:32`, `:48`, `:94`, `:105`) and confirm no other site has a live child alias across the check. If the audit turns up a deviation from the table, correct the table in `design.md` and add the corresponding red test to group 1 before fixing it.
- [ ] 2.4 Add `testInsertOnSingleOwnerMultiLevelRopeKeepsOnPathNodeIdentity` to `Tests/TextRopeTests/TextRopeInsertTests.swift` — same 20×2048 template and shape assertion, `insert("x", at: 100)`, on-path identity for root / inner child / leaf. This pins `openspec/specs/rope-insert/spec.md:48-50`, which was correct but untested. **Expected: green both before and after 2.1** (the insert descent already reads only `summary.utf16`).
- [ ] 2.5 Add `testReplaceOnSingleOwnerMultiLevelRopeKeepsOnPathNodeIdentity` to `Tests/TextRopeTests/TextRopeReplaceTests.swift` — same template, `replace(range: NSRange(location: 100, length: 10), with: "xyz")`. This pins `openspec/specs/rope-replace/spec.md:88-90`. Note in the test's doc comment that `replace` composes `delete` first and so would have been red on HEAD.

## 3. Cover `TextRope: Equatable` (DEF-005)

These tests document behavior that is already correct; they are expected to pass on HEAD. If any of them fails, that is a **newly discovered defect** — file it in `DEFECTS.md` and do not fix it inline under this change.

- [ ] 3.1 Create `Tests/TextRopeTests/TextRopeEqualityTests.swift` (`import XCTest`, `@testable import TextRope`, `final class TextRopeEqualityTests: XCTestCase`), matching the style of `TextRopeCOWTests.swift`.
- [ ] 3.2 Add `testRopesWithSameContentAreEqual` (two independent `TextRope(_:)` constructions from one string, both larger than `maxChunkUTF8` so the comparison is not a single-leaf trivial case) and `testEmptyRopesAreEqual` (`TextRope()` vs `TextRope("")`).
- [ ] 3.3 Add `testRopesWithSameContentButDifferentTreeShapesAreEqual`: build rope A with one `TextRope(_:)` call over a >4 KB string; build rope B holding identical content by starting from a prefix and applying incremental `insert` calls that drive splits at different offsets. Assert the leaf partitions actually differ (compare the leaf `chunk.utf8.count` vector, or `root.height`) **before** asserting `A == B`, so the test cannot silently degrade into 3.2.
- [ ] 3.4 Add `testRopesWithDifferentContentAreNotEqual`, and `testRopesWithSameUTF16CountButDifferentContentAreNotEqual` — two strings with identical utf8 count, utf16 count, and newline count but different characters, so no summary-based early-out (DEF-010) could ever satisfy it by comparing summaries alone.
- [ ] 3.5 Add `testCopyWithSharedRootIsEqual`: `let a = TextRope(large); let b = a`, assert `a.root === b.root` (the `TextRope.swift:41` fast-path precondition), then assert `a == b`.
- [ ] 3.6 Run `swift test --filter TextRopeEqualityTests`; all green expected.

## 4. Concurrent COW on a multi-level rope (DEF-008)

Also expected to pass on HEAD — this is coverage for an untested guarantee, not remediation. Same rule as group 3 if anything fails.

- [ ] 4.1 Settle the shared template: 20 blocks of 2048 identical bytes joined (≈40 KB, height 2, `[8, 8, 4]` leaves under three inner children). Every test in this group asserts that shape before fanning out, so a future change to `maxChunkUTF8`/`maxChildren` fails loudly instead of silently reverting the coverage to a single-leaf case.
- [ ] 4.2 Create `Tests/TextRopeTests/TextRopeConcurrentCOWTests.swift` with `testConcurrentMutationsFromSharedMultiLevelTemplateAreIndependent`: `withTaskGroup` over ~64 tasks; each task takes `var local = template` **as the first statement inside the task body** (not in the spawning loop — design D6), mutates at its own distinct UTF-16 offset spread across different inner children and leaves, and returns its content; assert each result against a `String` oracle and assert the template's `content` is unchanged after the group drains. The test class must not be `@MainActor`-isolated.
- [ ] 4.3 Add `testTaskGroupParallelReplaceOnMultiLevelRope` to `Tests/TextBufferTests/SendableRopeBufferConcurrencyTests.swift` — the same design at `SendableRopeBuffer` level (which adds a per-copy `OperationLog`), leaving the existing single-leaf `testTaskGroupParallelReplace` in place as the shallow case.
- [ ] 4.4 Add doc comments to both new tests recording: the ThreadSanitizer invocation, why the copy is taken inside the task body, why the class must stay un-isolated, and that the cooperative pool's width (`activeProcessorCount`) determines whether the tasks actually run in parallel.
- [ ] 4.5 Run `swift test --filter TextRopeConcurrentCOWTests` and `swift test --filter SendableRopeBufferConcurrencyTests` unsanitized; both green.

## 5. Verification and bookkeeping

- [ ] 5.1 Run the full suite (`swift test`) and confirm no regression — in particular `TextRopeStressTests`, which allocates differently after 2.1 but asserts against a `String` oracle and structural invariants, neither of which is identity-sensitive.
- [ ] 5.2 Run `swift test --sanitize=thread --filter TextRopeConcurrentCOWTests` and `swift test --sanitize=thread --filter SendableRopeBufferConcurrencyTests`; record the result (clean / findings / inconclusive-because-serialized) in the commit message. A TSan finding here is a `TextRope` COW defect and must be filed in `DEFECTS.md`.
- [ ] 5.3 Update `DEFECTS.md`: set DEF-003, DEF-005, and DEF-008 to `fixed`, and add a one-line note to DEF-003 naming the tests that now pin the guarantee. Leave DEF-010's cross-reference to `TextRope.swift:39-43` intact — that defect stays `open`.
- [ ] 5.4 Add to `CHANGELOG.md` under the upcoming patch release: a `Fixed` entry for the single-owner delete pessimization (DEF-003 — every delete path-copied regardless of ownership) and a `Changed` entry for the new `TextRope` equality and multi-level concurrent-COW coverage.
- [ ] 5.5 Run `openspec validate fix-rope-cow-and-equality-coverage --strict` and confirm the change is clean before archiving.
