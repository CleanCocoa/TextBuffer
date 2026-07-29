## Context

TextBuffer's two milestones are structurally independent (ADR-001, ADR-002):

- **Milestone 1** delivers `TransferableUndoable<Base>` — a generic undo/transfer decorator backed by a value-type `OperationLog`. The `snapshot()` and `represent(_:)` APIs enable buffer transfer by copying the log (SPEC.md §4.2).
- **Milestone 2** delivers `RopeBuffer` — a `Buffer` conformer wrapping `TextRope`, with UTF-8 internal storage and cached UTF-16 counts for O(log n) NSRange operations (SPEC.md §4.3, ADR-004).

The milestones converge at TASK-021: verifying that `TransferableUndoable<RopeBuffer>` composes correctly. Because `TransferableUndoable` is generic over `Buffer` and the `OperationLog` replays operations through the `Buffer` protocol's `insert`/`delete`/`replace` methods, this should work mechanically. The integration tests prove it does.

## Goals / Non-Goals

**Goals:**
- Prove `TransferableUndoable<RopeBuffer>` produces correct undo/redo behavior
- Prove `snapshot()` from a rope-backed buffer yields an independent `MutableStringBuffer`-backed copy with identical content, selection, and undo history
- Prove `represent(_:)` can load state from a `MutableStringBuffer`-backed snapshot into a rope-backed buffer and vice versa
- Prove undo equivalence: identical `BufferStep` sequences on `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>` produce identical results
- Exercise multi-byte Unicode content (emoji, CJK, combining marks) to stress UTF-8/UTF-16 translation at the rope boundary

**Non-Goals:**
- Performance benchmarking of rope vs string buffers (future work)
- Testing PuppetUndoManager with RopeBuffer (AppKit integration is orthogonal — PuppetUndoManager delegates to `TransferableUndoable` regardless of base type)
- Adding new public API — all tested APIs already exist
- Modifying RopeBuffer or TransferableUndoable implementations

## Decisions

### 1. Test structure: single integration test file

All convergence tests go in `Tests/TextBufferTests/RopeTransferIntegrationTests.swift` as specified in TASKS.md. This file exercises cross-type interactions that don't belong in either the Milestone 1 or Milestone 2 unit test suites. The test class is `@MainActor` (required by `TransferableUndoable` and `Buffer` conformers).

### 2. Leverage existing `assertUndoEquivalence` infrastructure

SPEC.md §4.4 defines `assertUndoEquivalence(reference:subject:steps:)` which runs identical `BufferStep` sequences on two buffers and asserts content + selection equality after every step. For convergence, we extend this pattern in two ways:

- **Rope ↔ String equivalence**: Run the same `BufferStep` array on `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>`, asserting identical content and selection after each step. This is a manual assertion loop (the existing helper hardcodes `Undoable` as reference type).
- **Cross-type transfer round-trips**: Snapshot from rope, represent into rope, then verify state preservation including undo history by performing undo/redo after transfer.

### 3. Test scenarios cover the three critical composition seams

The integration tests target three seams where Milestone 1 and Milestone 2 interact:

1. **OperationLog replay through RopeBuffer** — Undo/redo calls `insert`/`delete`/`replace` on `RopeBuffer` via the generic `Buffer` protocol. The rope's UTF-8 storage and B-tree structure are invisible to the log, but offset calculations during replay must agree with rope's UTF-16 counting.

2. **snapshot() content extraction** — `snapshot()` calls `MutableStringBuffer(wrapping: base)` which reads `base.content` (a full O(n) rope traversal) and `base.selectedRange`. The resulting `MutableStringBuffer` holds a flat `NSMutableString` copy.

3. **represent(_:) content injection** — `represent(_:)` calls `base.replace(range: base.range, with: source.content)` which does a full-range replace on the rope, plus copies `selectedRange` and the `OperationLog`. Post-represent, undo operations replay through the *target* buffer's `insert`/`delete`/`replace`.

### 4. Unicode stress cases are mandatory

Because RopeBuffer uses UTF-8 internally while the Buffer protocol uses UTF-16 (NSRange), every test scenario should include multi-byte content. ADR-004 notes that UTF-16 offset translation happens at leaf level — off-by-one errors in surrogate pair counting would only surface with content above U+FFFF (emoji, some CJK). Tests MUST include such content.

## Risks / Trade-offs

- **[Risk] OperationLog replays absolute UTF-16 offsets** → If the rope's `utf16Count` or `content(in:)` disagree with `MutableStringBuffer`'s NSRange interpretation for edge cases (e.g., CRLF at chunk boundaries), undo replay could corrupt content. **Mitigation**: The drift tests from TASK-020 already validate RopeBuffer ≡ MutableStringBuffer for all Buffer operations. Convergence tests add undo replay on top.

- **[Risk] represent() does a full-range replace** → For large documents, this is O(n) regardless of buffer type. **Mitigation**: Accepted by design (ADR-002 notes this). Performance optimization is out of scope for TASK-021.

- **[Trade-off] No dedicated assertUndoEquivalence variant for rope** → Rather than building a generic multi-buffer equivalence helper, tests use manual assertion loops. This avoids over-engineering the test infrastructure for a single integration test file.
