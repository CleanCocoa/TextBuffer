# Implementation Tasks: TextBuffer — Rope

**Source:** [SPEC.md](SPEC.md) §7
**Date:** 2026-03-11

---

## Milestone 1: Operation Log — Complete (0.3.0)

Shipped in 0.3.0. Implemented `BufferOperation`, `UndoGroup`, `OperationLog` value types; `TransferableUndoable<Base>` with auto-grouping, `undoGrouping`, and `modifying(affectedRange:_:)`; `PuppetUndoManager` for AppKit integration; `snapshot()`/`represent(_:)` transfer API; `assertUndoEquivalence` test infrastructure; undo equivalence drift tests; transfer integration tests. See CHANGELOG.md.

---

## Milestone 2: Rope

### Phase 6: Rope Foundation

**TASK-010: TextRope target and package structure**
- Depends on:  —
- Size:        S
- Description: Add TextRope target (zero dependencies) and
               TextRopeTests to Package.swift. Add
               `@_exported import TextRope` in TextBuffer.
- Spec:        SPEC.md §3.1 (Package Structure)
- Files:       Package.swift
               Sources/TextRope/TextRope.swift (placeholder)
               Sources/TextBuffer/Exports.swift
               Tests/TextRopeTests/TextRopeTests.swift (placeholder)
- Acceptance:  `swift build` succeeds. `swift test` runs.

**TASK-011: Summary and Node types**
- Depends on:  TASK-010
- Size:        M
- Description: Implement `TextRope.Summary` (utf8, utf16, lines with
               add/subtract/of). Implement `TextRope.Node` as internal
               final class: summary, height, chunk (String), children
               (ContiguousArray<Node>), named constants, shallowCopy(),
               emptyLeaf(), ensureUniqueChild(at:).
               TextRope struct with `nonisolated(unsafe) var root: Node`,
               always-rooted (empty leaf).
- Spec:        SPEC.md §4.3 (Summary, Node, TextRope)
- ADR:         ADR-005, ADR-006, ADR-007
- Files:       Sources/TextRope/Summary.swift
               Sources/TextRope/Node.swift
               Sources/TextRope/TextRope.swift
               Tests/TextRopeTests/SummaryTests.swift
- Acceptance:  Summary arithmetic correct. Node creation works.
               shallowCopy produces independent node. emptyLeaf
               has zero summary.

**TASK-012: COW infrastructure**
- Depends on:  TASK-011
- Size:        M
- Description: Implement COW path-copying: `ensureUnique()` on TextRope,
               `ensureUniqueChild(at:)` on Node (extract → check →
               write back). Verify copy independence and shared subtree
               preservation.
- Spec:        SPEC.md §4.3 (TextRope — COW)
- ADR:         ADR-005
- Files:       Sources/TextRope/TextRope+COW.swift
               Tests/TextRopeTests/TextRopeCOWTests.swift
- Acceptance:  - Copy shares root (identity)
               - Mutating copy doesn't affect original
               - Path copying creates new nodes only along mutation path

**TASK-013: Leaf construction and content materialization**
- Depends on:  TASK-011
- Size:        M
- Description: Implement `TextRope.init(_ string:)` — split into
               chunks, build balanced tree. Enforce `\r\n` split
               invariant. Implement `content: String` (concatenate
               leaves), `utf16Count`, `utf8Count`, `isEmpty`.
- Spec:        SPEC.md §4.3 (TextRope)
- Files:       Sources/TextRope/TextRope+Construction.swift
               Sources/TextRope/TextRope+Content.swift
               Tests/TextRopeTests/TextRopeConstructionTests.swift
- Acceptance:  Round-trip: `TextRope(s).content == s` for empty,
               single char, multi-chunk, emoji, `\r\n` sequences.
               `utf16Count` matches `s.utf16.count`. `\r\n` never
               split across chunks.

### Phase 7: Rope Core Operations

**TASK-014: UTF-16 offset navigation**
- Depends on:  TASK-013
- Size:        L
- Description: Implement O(log n) findLeaf(utf16Offset:) and
               `content(in utf16Range: NSRange)`. Within leaf: translate
               UTF-16 offset to String.Index via utf16 view walk.
- Spec:        SPEC.md §4.3 (TextRope — UTF-16 navigation)
- ADR:         ADR-004
- Files:       Sources/TextRope/TextRope+Navigation.swift
               Tests/TextRopeTests/TextRopeNavigationTests.swift
- Acceptance:  content(in:) correct for single-leaf, multi-leaf,
               boundary, multi-byte/emoji/surrogate-pair, empty range,
               full range.

**TASK-015: Insert operation**
- Depends on:  TASK-012, TASK-014
- Size:        L
- Description: Implement `mutating insert(_:at:)`:
               ensureUnique → navigate → COW path → insert in leaf →
               split if oversized (respecting `\r\n`) → propagate
               splits → update summaries bottom-up.
- Spec:        SPEC.md §4.3 (TextRope — core operations)
- Files:       Sources/TextRope/TextRope+Insert.swift
               Sources/TextRope/Node+Split.swift
               Tests/TextRopeTests/TextRopeInsertTests.swift
- Acceptance:  Insert at start/middle/end. Leaf split. Cascading
               splits. Multi-byte boundaries. Summaries correct.
               COW: insert on shared rope doesn't affect copies.

**TASK-016: Delete operation**
- Depends on:  TASK-012, TASK-014
- Size:        L
- Description: Implement `mutating delete(in:)`:
               ensureUnique → navigate start/end → COW path → remove
               content → merge undersized leaves → propagate merges →
               update summaries.
- Spec:        SPEC.md §4.3 (TextRope — core operations)
- Files:       Sources/TextRope/TextRope+Delete.swift
               Sources/TextRope/Node+Merge.swift
               Tests/TextRopeTests/TextRopeDeleteTests.swift
- Acceptance:  Delete within leaf, spanning leaves. Leaf merge.
               Cascading merges. Delete all → empty leaf root.
               Summaries correct.

**TASK-017: Replace operation**
- Depends on:  TASK-015, TASK-016
- Size:        M
- Description: Implement `mutating replace(range:with:)`.
               Start with delete + insert composition. Optimize later
               if benchmarks warrant.
- Spec:        SPEC.md §4.3 (TextRope — core operations)
- Files:       Sources/TextRope/TextRope+Replace.swift
               Tests/TextRopeTests/TextRopeReplaceTests.swift
- Acceptance:  Replace within leaf, spanning leaves. Shorter/longer
               replacement. Empty string = delete. Empty range = insert.
               Summaries correct.

### Phase 8: Rope Verification

**TASK-018: Rope comprehensive test suite**
- Depends on:  TASK-013 through TASK-017
- Size:        L
- Description: Comprehensive tests: construction (various sizes),
               content round-trip (ASCII, multi-byte, emoji, CJK),
               insert/delete/replace edge cases, COW independence,
               summary correctness, `\r\n` invariant, surrogate pairs,
               rebalancing, stress test (10K random operations vs
               equivalent String operations).
- Files:       Tests/TextRopeTests/TextRopeStressTests.swift
- Acceptance:  All tests pass. Stress test produces no mismatches.

### Phase 9: Buffer Integration

**TASK-019: RopeBuffer — Buffer conformance wrapper**
- Depends on:  TASK-017
- Size:        M
- Description: Implement `RopeBuffer` in TextBuffer target per
               SPEC.md §4.3. Wraps TextRope + selectedRange. Conforms
               to Buffer. Selection adjustment logic identical to
               MutableStringBuffer. TextAnalysisCapable via content
               extraction.
- Spec:        SPEC.md §4.3 (RopeBuffer)
- Files:       Sources/TextBuffer/Buffer/RopeBuffer.swift
               Tests/TextBufferTests/RopeBufferTests.swift
- Acceptance:  Compiles. Basic operations work. Selection adjustment
               matches MutableStringBuffer.

**TASK-020: RopeBuffer drift tests**
- Depends on:  TASK-019
- Size:        M
- Description: Port `BufferBehaviorDriftTests` to run RopeBuffer
               against MutableStringBuffer. Same scenarios: insert
               before/at/after cursor, selection interactions,
               sequential operations, mixed insert/delete.
- Files:       Tests/TextBufferTests/RopeBufferDriftTests.swift
- Acceptance:  All drift tests pass. RopeBuffer ≡ MutableStringBuffer.

---

## Convergence

**TASK-021: TransferableUndoable\<RopeBuffer\> integration**
- Depends on:  TASK-018, TASK-020
- Size:        M
- Description: Verify `TransferableUndoable<RopeBuffer>`:
               - Undo/redo on rope-backed buffer
               - snapshot() from RopeBuffer to MutableStringBuffer
               - represent() from MutableStringBuffer into RopeBuffer
               - Undo equivalence across buffer types
               Proves both milestones compose correctly.
- Spec:        SPEC.md §4.2, §4.3
- Files:       Tests/TextBufferTests/RopeTransferIntegrationTests.swift
- Acceptance:  All tests pass. Three buffer types interchangeable
               via snapshot/represent.

---

## Dependency Graph

```
Milestone 2 (Rope):

TASK-010 ──► TASK-011 ──┬──► TASK-012 ──┐
                        └──► TASK-013 ──┼──► TASK-014 ──┬──► TASK-015
                                        │               └──► TASK-016
                                        │                      │
                                        │               TASK-015 + 016
                                        │                   ──► TASK-017
                                        │                         │
                                        └──► TASK-018 ◄──────────┘
                                                │
                                        TASK-017 ──► TASK-019 ──► TASK-020

Convergence:

TASK-018 + TASK-020 ──► TASK-021

Critical path: 010 → 011 → 013 → 014 → 015 → 017 → 018 → 019 → 020 → 021
```

## Risk-Ordered Priorities

| Risk | Severity | Mitigating Task |
|---|---|---|
| COW path-copying bugs in rope | High | TASK-012, TASK-018 (stress tests) |
| UTF-16 ↔ UTF-8 offset translation | Medium | TASK-014 (surrogate pair edge cases) |
| Rope rebalancing correctness | High | TASK-015, 016, 018 |
