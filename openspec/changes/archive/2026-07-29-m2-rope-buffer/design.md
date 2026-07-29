## Context

The TextRope data structure (Milestone 2, TASK-010 through TASK-018) provides O(log n) insert/delete/replace on a balanced B-tree of UTF-8 chunks with cached UTF-16 summaries. To integrate rope-backed storage into the existing buffer ecosystem — where `Buffer` conformers power undo, transfer, and AppKit integration — a thin wrapper type is needed.

SPEC.md §4.3 defines `RopeBuffer` as a `final class` conforming to `Buffer` and `TextAnalysisCapable`, wrapping a `TextRope` and a `selectedRange: NSRange`. The existing `BufferBehaviorDriftTests` pattern (which asserts `MutableStringBuffer ≡ NSTextViewBuffer`) provides the template for proving behavioral equivalence.

This change covers TASK-019 (RopeBuffer implementation) and TASK-020 (drift tests).

## Goals / Non-Goals

**Goals:**
- Implement `RopeBuffer` per SPEC.md §4.3 with `Buffer` + `TextAnalysisCapable` conformance
- Selection adjustment logic identical to `MutableStringBuffer` (same `shifted(by:)` / `subtract` / `subtracting` calls)
- Drift test suite proving `RopeBuffer ≡ MutableStringBuffer` across all edit and selection scenarios
- `RopeBuffer` usable as a generic `Base` for `TransferableUndoable<RopeBuffer>` (verified in TASK-021, out of scope here)

**Non-Goals:**
- TransferableUndoable integration (TASK-021)
- Modifying the TextRope API or internals
- Performance benchmarking (correctness-only scope)
- Any AppKit integration for RopeBuffer (remains in-memory only)

## Decisions

### D1: RopeBuffer as `final class` (not struct)

Per SPEC.md §4.3, `RopeBuffer` is a `final class`. This matches `MutableStringBuffer` — Buffer conformers are reference types because they hold mutable state (`selectedRange`) and are passed to `TransferableUndoable<Base>` and `Undoable<Base>` which expect identity-stable bases. No alternative considered; this is a settled decision from the spec.

### D2: Selection adjustment via existing NSRange extensions

`MutableStringBuffer` uses `NSRange.shifted(by:)`, `NSRange.subtract(_:)`, and `NSRange.subtracting(_:)` — all defined in `NSRange+Shifted.swift` and `NSRange+Subtracting.swift`. `RopeBuffer` SHALL use the exact same calls with the exact same conditions:

- **insert:** `selectedRange.shifted(by: location <= selectedRange.location ? content.utf16.count : 0)`
- **delete:** `selectedRange.subtract(deletedRange)`
- **replace:** `selectedRange.subtracting(replacementRange).shifted(by: replacementRange.location <= selectedRange.location ? content.utf16.count : 0)`

This is a direct copy of the `MutableStringBuffer` selection adjustment pattern, not a reinterpretation.

### D3: TextAnalysisCapable via default implementations

`TextAnalysisCapable` provides default `wordRange(for:)` and `lineRange(for:)` implementations when `Range == NSRange` and `Content == String`. Since `RopeBuffer` satisfies both constraints, it gets these defaults automatically. `RopeBuffer` needs only declare `lineRange(for:)` (which delegates to its content as NSString) — or it may rely on the protocol extension default. The `MutableStringBuffer` pattern provides its own `lineRange(for:)` via `self.storage.lineRange(for:)` because it has direct access to NSMutableString. `RopeBuffer` can use the protocol extension default which operates on `self.content as NSString`.

### D4: Drift test pattern — direct pair comparison

The drift tests follow the established `BufferBehaviorDriftTests` structure:
1. Create a `(RopeBuffer, MutableStringBuffer)` pair with identical initial content and selection
2. Apply the same operation to both
3. Assert `content` and `selectedRange` are equal after each operation

This does NOT require `#if os(macOS)` gating — both `RopeBuffer` and `MutableStringBuffer` are cross-platform. Unlike the existing drift tests (which require AppKit for `NSTextViewBuffer`), the rope drift tests can run on all platforms.

### D5: No `@MainActor` on RopeBuffer

`MutableStringBuffer` is not `@MainActor`-isolated. `RopeBuffer` follows the same pattern. `TextRope` is `Sendable`, but `RopeBuffer` as a `final class` with mutable state (`selectedRange`) is not automatically Sendable. Following `MutableStringBuffer`'s precedent, it will have `@available(*, unavailable) extension RopeBuffer: @unchecked Sendable {}` to explicitly opt out.

## Risks / Trade-offs

- **[Risk] TextRope API not yet implemented** → This change assumes TASK-017 (TextRope core) is complete. If TextRope APIs are missing or differ from SPEC.md §4.3, RopeBuffer implementation will need to adapt. Mitigation: TASK-019 explicitly depends on TASK-017.
- **[Risk] `content` property is O(n) on TextRope** → `TextAnalysisCapable` default implementations use `self.content as NSString`, which materializes the full rope. For this change, correctness is the goal; performance optimization (e.g., rope-native line/word range) is a future concern.
- **[Risk] Range validation differences** → `MutableStringBuffer` validates ranges against `self.storage.length`; `RopeBuffer` validates against `rope.utf16Count`. If `TextRope.utf16Count` has edge-case differences from `NSMutableString.length`, drift tests will catch it.
