# Implementation Tasks: TextBuffer — Operation Log & Rope

**Source:** [SPEC.md](SPEC.md) §7
**Date:** 2026-03-11

Tasks are ordered by dependency. Each task references SPEC.md sections for
type definitions and behavioral contracts. See SPEC.md §7.1 for the phase
overview and §7.3–7.4 (below) for the dependency graph and risk priorities.

Milestone 1 (TASK-001 through TASK-009) and Milestone 2 (TASK-010 through
TASK-020) can be developed in parallel branches. TASK-021 requires both.

---

## Milestone 1: Operation Log

### Phase 1: Test Infrastructure

**TASK-001: BufferStep enum and equivalence test scaffolding**
- Depends on:  —
- Size:        S
- Description: Create the `BufferStep` enum (insert, delete, replace,
               select, undo, redo, group) in TextBufferTesting. Create
               `assertUndoEquivalence` that takes an
               `Undoable<MutableStringBuffer>` and
               `TransferableUndoable<MutableStringBuffer>`, iterates
               steps, applies each to both buffers via static dispatch,
               and asserts content + selection equality after each step.
               `TransferableUndoable` doesn't exist yet — guard with
               `#if false` or a stub type.
- Files:       Sources/TextBufferTesting/BufferStep.swift
               Sources/TextBufferTesting/AssertUndoEquivalence.swift
- Acceptance:  File compiles (with guard). Enum covers all cases.
               Assertion function structure is reviewable.

**TASK-002: High-level transfer tests (failing)**
- Depends on:  TASK-001
- Size:        M
- Description: Write three integration tests from plan.md as failing
               tests:
               Test A: transfer-out preserves undo (editor inserts
               twice → snapshot → undo on copy → verify).
               Test B: transfer-in preserves undo (in-memory buffer
               with changes → represent in editor → undo → verify).
               Test C: transitivity (in-memory → represent → snapshot
               → all three undo/redo identically).
               Guarded until API exists.
- Files:       Tests/TextBufferTests/TransferIntegrationTests.swift
- Acceptance:  Test file present, documents three scenarios. Guarded.

### Phase 2: Core Value Types

**TASK-003: BufferOperation and UndoGroup**
- Depends on:  —
- Size:        S
- Description: Implement `BufferOperation` (enum Kind with insert,
               delete, replace) and `UndoGroup` (operations array,
               selectionBefore, selectionAfter, actionName). Both
               Sendable, Equatable, value types.
- Spec:        SPEC.md §4.2 (BufferOperation, UndoGroup)
- Files:       Sources/TextBuffer/OperationLog/BufferOperation.swift
               Sources/TextBuffer/OperationLog/UndoGroup.swift
- Acceptance:  Types compile. Equatable works.

**TASK-004: OperationLog**
- Depends on:  TASK-003
- Size:        L
- Description: Implement `OperationLog` as a value type per
               SPEC.md §4.2: history array + cursor for undo/redo,
               grouping stack for nested recording,
               beginUndoGroup/endUndoGroup/record,
               undo(on:)/redo(on:) generic over Buffer.
               Inverse operations use preconditionFailure on errors.
- Spec:        SPEC.md §4.2 (OperationLog)
- Files:       Sources/TextBuffer/OperationLog/OperationLog.swift
               Tests/TextBufferTests/OperationLogTests.swift
- Acceptance:  Unit tests covering:
               - Single operation undo/redo round-trip
               - Multi-operation group undo/redo
               - Nested groups merge into parent
               - Redo tail truncation on new edit after undo
               - canUndo/canRedo state transitions
               - Action name propagation (nested promotes to parent)
               - selectionBefore restored on undo
               - selectionAfter restored on redo
               - Undo then redo = identity (no observable difference)
               - Value-type copy independence

### Phase 3: TransferableUndoable

**TASK-005: TransferableUndoable — core Buffer conformance**
- Depends on:  TASK-004
- Size:        L
- Description: Implement `TransferableUndoable<Base>` per SPEC.md §4.2.
               Each insert/delete/replace: auto-group if not grouping,
               capture old content, delegate to base, record to log.
               `undoGrouping` with nesting. `undo()`/`redo()` delegate
               to log + restore selection. Does NOT include puppet
               bridge or transfer API yet.
- Spec:        SPEC.md §4.2 (TransferableUndoable)
- Files:       Sources/TextBuffer/Buffer/TransferableUndoable.swift
               Tests/TextBufferTests/TransferableUndoableTests.swift
- Acceptance:  Unit tests:
               - insert/delete/replace produce undoable operations
               - undo restores content + selection exactly
               - redo restores content + selection exactly
               - undo then redo = no observable change
               - undoGrouping groups multiple ops as one undo step
               - Nested undoGrouping works
               All tests use MutableStringBuffer as Base.

**TASK-006: Undo equivalence drift tests**
- Depends on:  TASK-001, TASK-005
- Size:        M
- Description: Unguard `assertUndoEquivalence`. Write equivalence
               tests running identical step sequences on
               `Undoable<MutableStringBuffer>` (gold standard) and
               `TransferableUndoable<MutableStringBuffer>` (subject).
               Scenarios: simple insert/undo/redo, delete, replace,
               grouped operations, interleaved edits and undos,
               multiple undos then new edit (redo tail truncation),
               selection state at every step.
- Spec:        SPEC.md §4.4 (Testing Infrastructure)
- Files:       Tests/TextBufferTests/UndoEquivalenceDriftTests.swift
               Sources/TextBufferTesting/AssertUndoEquivalence.swift
- Acceptance:  All equivalence tests pass.

### Phase 4: AppKit Bridge

**TASK-007: PuppetUndoManager and system integration**
- Depends on:  TASK-005
- Size:        M
- Description: Implement `PuppetUndoManager` as NSUndoManager subclass
               per SPEC.md §4.2. Override undo/redo/canUndo/canRedo/
               undoActionName/redoActionName to delegate via
               `PuppetUndoManagerDelegate`. Override `registerUndo`
               variants as no-ops. Add `enableSystemUndoIntegration()`
               to `TransferableUndoable`. Document app-side wiring:
               `textView.allowsUndo = false`,
               `NSTextViewDelegate.undoManager(for:) → puppet`.
- Spec:        SPEC.md §4.2 (PuppetUndoManager), §5.3 (AppKit Integration)
- ADR:         ADR-003
- Files:       Sources/TextBuffer/Buffer/PuppetUndoManager.swift
               Sources/TextBuffer/Buffer/TransferableUndoable.swift
               Tests/TextBufferTests/PuppetUndoManagerTests.swift
- Acceptance:  - puppet.canUndo/canRedo reflect log state
               - puppet.undoActionName/redoActionName reflect log
               - puppet.undo() triggers log undo
               - Edit menu shows correct action name
               - Edit > Undo grays out when log is empty
               - NSTextView with allowsUndo=false doesn't register
                 its own actions on the puppet
               - Integration test: NSTextView in window, Cmd+Z works

### Phase 5: Transfer API

**TASK-008: Transfer API — snapshot and represent**
- Depends on:  TASK-005
- Size:        M
- Description: Add `snapshot()` and `represent(_:)` to
               `TransferableUndoable` per SPEC.md §4.2.
               `snapshot()` creates `MutableStringBuffer(wrapping:)`,
               copies log. `represent()` preconditions `!log.isGrouping`,
               replaces content via `base.replace`, sets selection,
               copies source log.
- Spec:        SPEC.md §4.2 (Transfer — snapshot, Transfer — represent)
- ADR:         ADR-002
- Files:       Sources/TextBuffer/Buffer/TransferableUndoable.swift
               Tests/TextBufferTests/TransferAPITests.swift
- Acceptance:  - snapshot produces independent copy
               - Mutating copy doesn't affect original (and vice versa)
               - represent replaces content, selection, undo history
               - represent + undo restores source's previous state
               - represent + redo after undo restores source's state

**TASK-009: Transfer integration tests**
- Depends on:  TASK-008, TASK-002
- Size:        M
- Description: Unguard and complete the three integration tests:
               Test A: transfer-out preserves undo.
               Test B: transfer-in preserves undo.
               Test C: transitivity.
               Plus: snapshot during active puppet bridge, represent
               clears previous undo state.
- Files:       Tests/TextBufferTests/TransferIntegrationTests.swift
- Acceptance:  All three integration tests pass.

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
               emptyLeaf(), ensureUniqueChild(at:), summary(for:).
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
- Depends on:  TASK-008, TASK-019
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
Milestone 1 (Operation Log):

TASK-001 ──► TASK-002
                │
TASK-003 ──► TASK-004 ──► TASK-005 ──┬──► TASK-006
                                     ├──► TASK-007
                                     └──► TASK-008 ──► TASK-009

Milestone 2 (Rope) — parallel from TASK-010:

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

TASK-008 + TASK-019 ──► TASK-021

Critical path (M1): 003 → 004 → 005 → 008 → 009
Critical path (M2): 010 → 011 → 013 → 014 → 015 → 017 → 019 → 020
Overall:            Both paths → 021
```

## Risk-Ordered Priorities

| Risk | Severity | Mitigating Task |
|---|---|---|
| OperationLog undo/redo correctness | High | TASK-004 (unit tests), TASK-006 (equivalence) |
| COW path-copying bugs in rope | High | TASK-012, TASK-018 (stress tests) |
| UTF-16 ↔ UTF-8 offset translation | Medium | TASK-014 (surrogate pair edge cases) |
| Rope rebalancing correctness | High | TASK-015, 016, 018 |
| PuppetUndoManager AppKit interop | Medium | TASK-007 (NSTextView integration test) |
