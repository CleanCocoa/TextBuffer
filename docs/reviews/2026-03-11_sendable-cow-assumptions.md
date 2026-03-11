# Review Report: Sendable & COW Assumptions

**Date:** 2026-03-11
**Reviewer:** spec-reviewer (AI-assisted)
**Status:** Reviewed — suggestions recorded

---

## Assumptions Under Review

1. **Buffer types should conform to `Sendable`** (copies are independent, safe to pass across concurrency boundaries). If impractical, use `@unchecked Sendable` wrapper.
2. **Buffer copies should use copy-on-write internally** so that per-keystroke snapshot creation is O(1). The actual memory copy defers to first mutation.

---

## Findings

### Assumption 1: Sendable

**Partially satisfiable.** The value types that carry data across boundaries are already `Sendable`:

| Type | Sendable | Notes |
|------|----------|-------|
| `TextRope` | ✅ | Value type, COW via `nonisolated(unsafe) var root` |
| `OperationLog` | ✅ | Value type, Swift array COW |
| `UndoGroup` | ✅ | Value type |
| `BufferOperation` | ✅ | Value type |
| `NSRange` | ✅ | Trivial value type |

The `Buffer`-conforming wrappers are **not meaningfully Sendable**:

| Type | Why not |
|------|---------|
| `MutableStringBuffer` | Wraps `NSMutableString`; `Sendable` explicitly `@unavailable` |
| `NSTextViewBuffer` | `@MainActor open class`; actor-isolated, not transferable |
| `TransferableUndoable<Base>` | `@MainActor final class`; holds mutable reference-type base |

**Conclusion:** The `Buffer` protocol requires `AnyObject` and mutable state — it is the wrong abstraction layer for cross-concurrency transfer. The correct boundary is the *snapshot data*, not the buffer itself. A value-type tuple of `(TextRope, NSRange, OperationLog)` is fully `Sendable` and O(1) to copy. The `@MainActor` isolation on buffer wrappers is the correct concurrency story for those types — they are safe because they are confined, not because they are transferable.

**No spec or ADR change needed.** The assumption is satisfied at the data layer where it matters. Forcing `Sendable` onto `Buffer` conformers would be unsound.

### Assumption 2: COW for O(1) Snapshots

**Not currently satisfied in Milestone 1. Satisfiable after Milestone 2.**

The current `snapshot()` signature is:

```swift
public func snapshot() -> TransferableUndoable<MutableStringBuffer>
```

This forces an O(n) `NSMutableString` copy via `MutableStringBuffer(wrapping:)`, even when the underlying storage is a `TextRope` with O(1) COW. The `OperationLog` copy is already O(1) (Swift array COW), so the bottleneck is entirely in the content copy.

After Milestone 2, if `snapshot()` returned `TransferableUndoable<RopeBuffer>` (or were generic), copying a `RopeBuffer` would mean copying a `TextRope` struct (O(1) root pointer copy) + an `NSRange` (trivial). True O(1) per-keystroke snapshots.

**Trade-off:** O(1) snapshot creation moves the O(n) cost to `represent(_:)`, where the rope must be materialized into the `NSTextView`. This is the right trade-off — snapshots happen per-keystroke; document switches are infrequent.

**The spec is underspecified here, not wrong.** The hardcoded `MutableStringBuffer` return type is correct for Milestone 1 (no rope yet). The spec doesn't describe what happens post-convergence. ADR-002 already notes "the rope's internal representation can switch" but doesn't address the snapshot return type.

---

## Suggestion: Record `snapshot()` Genericity as a Story

The `snapshot()` return type should become generic after Milestone 2 convergence. Two options:

**Option A — Generic return matching base:**
```swift
// On TransferableUndoable<RopeBuffer>:
public func snapshot() -> TransferableUndoable<RopeBuffer>  // O(1)

// On TransferableUndoable<NSTextViewBuffer>:
public func snapshot() -> TransferableUndoable<RopeBuffer>  // O(n) to build rope
```

**Option B — Protocol-level associated type:**
```swift
// TransferableUndoable gains an associated snapshot type
public func snapshot() -> TransferableUndoable<SnapshotBuffer>
```

Either way, the key insight is: **the snapshot storage type should be the cheapest copyable representation**, which post-Milestone 2 is `RopeBuffer`, not `MutableStringBuffer`.

This does not change ADR-002's decision matrix — the operation log is still the right approach. It's a refinement of the transfer mechanics once the rope exists.

---

## ADR-002 Update

Added a note under Consequences acknowledging the snapshot return type is Milestone 1-scoped and will need revision post-rope convergence. No decision change.
