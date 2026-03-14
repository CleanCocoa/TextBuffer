## Why

Milestone 2 requires a `Buffer`-conforming wrapper around `TextRope` so rope-backed editing can participate in the same generic pipelines as `MutableStringBuffer` and `NSTextViewBuffer`. Without `RopeBuffer`, the rope data structure is a standalone storage engine with no integration path into the buffer/undo/transfer ecosystem. This change covers TASK-019 and TASK-020 from the master roadmap — the Buffer integration phase that precedes convergence (TASK-021).

## What Changes

- **New type `RopeBuffer`** — a `final class` in the TextBuffer target conforming to `Buffer` and `TextAnalysisCapable`. Wraps a `TextRope` instance for storage and maintains a `selectedRange: NSRange` for selection tracking. All edit operations (`insert`, `delete`, `replace`) delegate to `TextRope` and apply identical selection adjustment logic to `MutableStringBuffer` (shift-on-insert, subtract-on-delete, subtract-then-shift-on-replace).
- **Unit tests for `RopeBuffer`** — basic operation correctness tests in `RopeBufferTests.swift`.
- **Behavioral drift tests** — `RopeBufferDriftTests.swift` ports the existing `BufferBehaviorDriftTests` pattern to run `RopeBuffer` against `MutableStringBuffer`, asserting content and selection equivalence after every operation across all edit and selection scenarios.

## Capabilities

### New Capabilities
- `rope-buffer-conformance`: RopeBuffer as a Buffer + TextAnalysisCapable conformer wrapping TextRope, with NSRange-typed operations and MutableStringBuffer-identical selection adjustment logic
- `rope-buffer-drift`: Behavioral drift testing proving RopeBuffer ≡ MutableStringBuffer for all edit and selection scenarios

### Modified Capabilities
<!-- None — this change introduces new types without modifying existing capability requirements. -->

## Impact

- **New source file:** `Sources/TextBuffer/Buffer/RopeBuffer.swift`
- **New test files:** `Tests/TextBufferTests/RopeBufferTests.swift`, `Tests/TextBufferTests/RopeBufferDriftTests.swift`
- **Dependency:** TextBuffer target gains a dependency on TextRope target (for importing `TextRope`)
- **API surface:** One new public type (`RopeBuffer`) with the same API shape as `MutableStringBuffer`
- **Unlocks:** TASK-021 (TransferableUndoable\<RopeBuffer\> convergence) depends on this change completing successfully
