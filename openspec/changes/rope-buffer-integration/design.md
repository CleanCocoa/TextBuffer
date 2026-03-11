## Context

`TextRope` (TASK-010 through TASK-018) is a fully-tested, standalone B-tree of UTF-8 string chunks with O(log n) insert, delete, and replace via UTF-16 offset navigation. It is not yet wired to the `Buffer` protocol. Separately, `TransferableUndoable<Base>` (TASK-005 through TASK-009) provides operation-log-backed undo and buffer transfer — but has only ever been instantiated over `MutableStringBuffer` or `NSTextViewBuffer`.

This change closes the loop on Milestone 2 (TASK-019, TASK-020) and proves the two-milestone convergence (TASK-021). No new algorithmic decisions are needed; the design is almost entirely about wrapping, parity testing, and composition.

**Current state:**
- `TextRope` — complete, tested in `TextRopeTests`
- `TransferableUndoable` — complete with `snapshot()`/`represent()` API
- `MutableStringBuffer` — gold-standard for selection adjustment behaviour
- `BufferBehaviorDriftTests` — existing suite comparing `MutableStringBuffer` against `NSTextViewBuffer`

## Goals / Non-Goals

**Goals:**
- `RopeBuffer` conforming to `Buffer` (and `TextAnalysisCapable`) by wrapping `TextRope`
- Selection adjustment in `RopeBuffer` identical to `MutableStringBuffer` (verified by drift tests)
- `TransferableUndoable<RopeBuffer>` working end-to-end: undo/redo, `snapshot()` → `TransferableUndoable<MutableStringBuffer>`, `represent()` from `MutableStringBuffer` into `RopeBuffer`
- Drift test suite (`RopeBufferDriftTests`) porting the `BufferBehaviorDriftTests` scenarios so both backends are continuously regression-tested
- All new tests passing on `swift test` with no modification to existing sources

**Non-Goals:**
- Performance optimisation or benchmarking of `RopeBuffer` vs `MutableStringBuffer`
- Deprecation or removal of `MutableStringBuffer`
- New `Buffer` protocol methods or UTF-8 range support (out of scope for this change)
- AppKit integration for `RopeBuffer` (no `NSTextViewBuffer` equivalent needed yet)
- Changes to `OperationLog`, `TransferableUndoable`, or `TextRope` internals

## Decisions

### D1 — `RopeBuffer` as a `final class` mirroring `MutableStringBuffer`

`RopeBuffer` is a reference type (`final class`) to match the pattern of every existing `Buffer` conformer. The `@MainActor` isolation constraint on `Buffer` requires reference semantics for mutable shared state. `TextRope` is a value type internally (COW via `isKnownUniquelyReferenced`), so `RopeBuffer` simply owns one `TextRope` instance and one `NSRange` for selection.

**Alternative considered:** a `struct` with `@MainActor` stored property. Rejected — `Buffer` conformers are universally classes in this codebase; a struct conformer would require annotation gymnastics and would not compose naturally with `TransferableUndoable<Base>` (which expects stable identity via `let base: Base`).

### D2 — Selection adjustment copied verbatim from `MutableStringBuffer`

The three adjustment rules from `MutableStringBuffer`:
- **Insert before or at selection start**: shift `selectedRange` right by `insertedLength`
- **Delete with overlap into selection**: clamp and subtract; if deletion swallows selection, collapse to deletion start
- **Replace**: equivalent to delete-then-insert; apply both adjustments in sequence

The adjustment logic is not parameterised or abstracted — it is copied as a direct port. This keeps `RopeBuffer` self-contained and makes diffs against `MutableStringBuffer` readable during review.

**Alternative considered:** a shared `SelectionAdjusting` protocol or free function. Rejected for this change — premature abstraction with only two conformers. If a third rope-like buffer appears, extract then.

### D3 — Drift tests via `assertBufferEquivalence` helper, not `assertUndoEquivalence`

`RopeBufferDriftTests` targets buffer operation parity (content + selection after each mutation step), not undo-log parity. It does not need `BufferStep` or `assertUndoEquivalence` — it can simply call operations on both a `RopeBuffer` and a `MutableStringBuffer` with identical arguments and assert `content` and `selectedRange` equality after each step.

`assertUndoEquivalence` is reserved for TASK-006 (Milestone 1) and the convergence tests in TASK-021 where undo/redo behaviour across buffer types is what's under test.

### D4 — Convergence via `TransferableUndoable<RopeBuffer>` exercising the full transfer matrix

TASK-021 must cover four transfer paths:
1. Undo/redo on `TransferableUndoable<RopeBuffer>` directly
2. `snapshot()` from `TransferableUndoable<RopeBuffer>` → `TransferableUndoable<MutableStringBuffer>`
3. `represent()` loading `TransferableUndoable<MutableStringBuffer>` state into `TransferableUndoable<RopeBuffer>`
4. Transferable-undo equivalence: the same `BufferStep` sequence on `TransferableUndoable<RopeBuffer>` and `TransferableUndoable<MutableStringBuffer>` produces identical content + selection at every step

Path 4 uses a dedicated cross-type helper with static dispatch for the two concrete transferable-undo variants. It must not assume the existing `assertUndoEquivalence` helper is generic over arbitrary buffer bases.

### D5 — `TextAnalysisCapable` conformance via existing default implementations

`RopeBuffer` conforms to `TextAnalysisCapable` because it has `Range == NSRange` and `Content == String`, so the existing protocol extension provides `wordRange(for:)` and `lineRange(for:)` automatically via `content`. No rope-native analysis is implemented in this change.

## Risks / Trade-offs

**Selection adjustment drift** — If the copy of MutableStringBuffer's selection logic is subtly wrong in `RopeBuffer`, drift tests will catch it. The risk is low because the logic is a direct port, but the tests are the safety net.
→ Mitigation: drift test every combination from `BufferBehaviorDriftTests` (insert before/at/after cursor, delete overlapping, replace scenarios, empty-buffer edge cases).

**`snapshot()` cross-type correctness** — `snapshot()` materialises `rope.content` into a `MutableStringBuffer` and copies the `OperationLog` value. The log contains `BufferOperation.insert/delete/replace` values that are replayed on the target buffer's API. Since both `RopeBuffer` and `MutableStringBuffer` implement the same `Buffer` protocol methods, replay correctness is guaranteed by the protocol contract.
→ Mitigation: convergence test (TASK-021) explicitly verifies that undo on the snapshot produces the same content as undo on the original rope-backed buffer.

**`represent()` O(n) content replacement** — `represent()` calls `base.replace(range: base.range, with: source.content)`, which materialises the full rope content and replaces the entire TextRope in one operation. For this change this is acceptable — `represent()` is a document-switch operation, not a per-keystroke mutation.
→ No mitigation needed; consistent with the existing `TransferableUndoable` design (ADR-002).

**Rope rebalancing during test replay** — Under the dedicated cross-type transferable-undo equivalence helper, the operation log is replayed on a `RopeBuffer`. If a sequence of inserts and deletes causes many rebalances, the tree structure diverges from a simple string — but `content` output must remain identical. The stress tests in TASK-018 already validate this property for `TextRope`; drift tests in TASK-020 confirm it holds at the `Buffer` API surface.
→ Mitigation: port stress-test-scale scenarios into `RopeBufferDriftTests` (large document, many random edits).

## Open Questions

None. All design decisions are resolved by the existing SPEC.md, ADR corpus, and the requirement that `RopeBuffer` be a drop-in behavioural substitute for `MutableStringBuffer`.
