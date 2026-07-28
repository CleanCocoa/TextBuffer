# Changelog

## 0.8.0

### Added

- `NSTextViewOperationLogBridge.shouldChangeText(inRanges:replacementStrings:)` — plural funnel for `NSTextViewDelegate.textView(_:shouldChangeTextInRanges:replacementStrings:)`. A single-range forward delegates to the singular funnel; an edit spanning more than one range (multiple insertion points, find-and-replace-all) marks the log for discard at the next `textDidChange()` — drop history rather than record a delta that would not replay. Hosts forwarding only the singular method get the divergence discard only while an edit is staged; forward the plural method too so multi-range edits can never leave the log silently stale.
- Undo groups that open a coalescing run (single-character inserts, deletes) are named "Typing" (unlocalized), so a system undo manager's `undoMenuItemTitle` yields "Undo Typing", matching native `NSTextView` undo. Multi-character inserts (paste) and replaces stay unnamed: the log cannot tell a paste from a drop, and a wrong name is worse than a bare "Undo".

### Fixed

- `PuppetUndoManager` swallows block-based `registerUndoWithTarget:handler:` like it already swallowed the selector-based form. Native registrations from a text view with `allowsUndo` enabled no longer accumulate (and retain their handlers) forever in the puppet's never-closed init group.
- `PuppetUndoManager.prepare(withInvocationTarget:)` returns a swallowing invocation target instead of `self`, so invoking a non-`UndoManager` selector on the result no-ops instead of crashing with `doesNotRecognizeSelector:`. Nothing is recorded either way.

## 0.7.0

### Added

- `NSTextViewOperationLogBridge` — mirrors `NSTextView` edits into an `OperationLog` while the text view stays the live content authority. Feed it by forwarding `shouldChangeText(in:replacementString:)` and `textDidChange()` from the view's delegate; `undo()`/`redo()` replay log groups back onto the view (content and selection) through `insertText(_:replacementRange:)` so the view re-emits its regular change callbacks; `enableSystemUndoIntegration()` returns a `PuppetUndoManager` for AppKit's Edit menu and Cmd+Z. Replay-driven view mutations are guarded against re-recording.
- macOS-style undo coalescing in `NSTextViewOperationLogBridge`: a continuous typing run records as one undo group, never one per keystroke; `breakUndoCoalescing()` is the public seam for forwarding interaction breaks (mouse-down, cursor repositioning, focus changes). Coalescing lives log-side as an extension of `OperationLog`'s per-edit auto-grouping, so it travels with snapshots; a run also ends on undo/redo, a kind or position mismatch, or an explicit group.
- Delete-run coalescing, matching native deletion undo: a backspace run extends while each delete ends where the previous one started; a forward-delete run extends at a constant location. Runs are same-kind only — a delete never joins an insert run and vice versa — and replace never coalesces.
- Multi-character inserts (paste) record their own undo group and close the typing run instead of joining it; a committed IME composition likewise never joins a preceding run nor opens one. An attribute-only change (`nil` replacement string) breaks the typing run, matching native formatting-during-typing behavior.
- `NSTextViewOperationLogBridge.sendableSnapshot()` — captures the view's content, selection, and the mirrored log as a `SendableRopeBuffer` for storage or transfer, mirroring `TransferableUndoable.sendableSnapshot()`. Restore by configuring a fresh view from the snapshot and handing its log to `init(textView:log:)`; the initializer closes any open typing run in the adopted log, so a re-presented buffer never resumes an old run.
- IME/marked-text gating in `NSTextViewOperationLogBridge`: composition intermediates record nothing while the view `hasMarkedText()`; the committed composition records exactly once, as one edit against the pre-composition baseline; a cancelled composition records nothing. A baseline left over by an unmark without a character-changing `textDidChange` is resolved (committed or discarded) before the next ordinary edit stages, so it cannot fold into stale composition math.
- Attribute-only edits (`nil` replacement string, no character changes) record nothing and leave the log replayable; a programmatic full replace records as exactly one undo group.

### Changed

- `OperationLog` equality compares recorded history only (history, cursor, grouping stack) and ignores whether a typing run is open, so a coalescing break never reads as a history change in snapshot comparisons.

## 0.6.0

### Added

- DocC documentation for all three library products: TextBuffer, TextRope, and TextBufferTesting each have a DocC catalog with a landing page and organized topic groups.
- "Choosing a Buffer" article — decision guide with comparison table and code examples, positioning `SendableRopeBuffer` as the recommended in-memory buffer.
- "Undo and Redo" article — explains both `UndoManager`-based and `OperationLog`-based strategies with code examples.
- Doc comments for previously undocumented public types: `TextBuffer` protocol, `RopeBuffer`, `SendableRopeBuffer`, `TransferableUndoable`, `PuppetUndoManager`, `OperationLog`, `UndoGroup`, `BufferOperation`, `BufferContent`, `TextRope`, and all TextBufferTesting helpers.

### Changed

- **BREAKING:** `InMemoryBuffer` typealias now points to `SendableRopeBuffer` (was `MutableStringBuffer`). The rope-backed, `Sendable` value type with built-in undo is the proper in-memory buffer for production use. `MutableStringBuffer` remains available by its concrete name.
- `EditingBuffer` typealias added for `TransferableUndoable<RopeBuffer>` — the `@MainActor` buffer for UI-connected editing with system undo integration.
- ADR-011: Multi-buffer in-memory architecture.

## 0.5.0

### Added

- `TextBuffer` protocol — base protocol without `AnyObject`, enabling struct conformers. `Buffer` refines it, so existing class conformers are unaffected.
- `SendableRopeBuffer` — `Sendable` value-type buffer combining `TextRope` + `OperationLog` + selection. Conforms to `TextBuffer`, `TextAnalysisCapable`, and `CustomStringConvertible`. Designed for concurrent batch processing via `TaskGroup`.
- `SendableRopeBuffer.comparator(_:_:...)` — factory returning `@Sendable` comparison closures. Callers choose components to compare (`.content`, `.selection`, `.undoHistory`).
- `OperationLog.popUndo()` / `popRedo()` — cursor manipulation methods for struct-based undo replay without exclusivity violations.
- `SendableRopeBuffer` conversion surface: `init(copying:)`, `init(from:)`, `toRopeBuffer()`, `toTransferableUndoable()`.
- `TransferableUndoable.sendableSnapshot()` / `represent(_: SendableRopeBuffer)` for round-trip snapshot transfer with undo history.
- `makeSendableRopeBuffer(_:)` factory in `TextBufferTesting`.
- `applyStep(_:to: inout SendableRopeBuffer)` and `assertSendableUndoEquivalence(initial:steps:)` for step-driven undo equivalence testing.
- ADR-010: Sendable value-type buffer via protocol split.

### Changed

- `TextAnalysisCapable` now refines `TextBuffer` instead of `Buffer`, enabling struct conformers to provide `wordRange`/`lineRange`.
- `assertBufferState`, `MutableStringBuffer.init(copying:)`, `RopeBuffer.init(copying:)` accept `TextBuffer` (widened from `Buffer`).
- `change(buffer:to:)` gains an `inout` overload for `TextBuffer` value types.

### Deprecated

- `change(buffer:to:)` non-`inout` overload — use `change(buffer: &buffer, to:)` instead.

### Fixed

- `Undoable`: replaced `isolated deinit` with nonisolated deinit using `MainActor.assumeIsolated`. The Swift 6.2 runtime aborts (signal 6) when a `@MainActor` class with `isolated deinit` is deallocated without a running RunLoop (XCTest CLI, background threads).
- TextRope: CRLF split invariant in delete's leaf merge.
- TextRope: precondition guards on public API for bounds checking.
- TextRope: tree invariant validation for oversized leaf siblings.

## 0.4.0

### Added

- `TextRope` — B-tree rope data structure with O(log n) insert, delete, and replace. UTF-8 storage with cached UTF-16 counts. Value semantics with copy-on-write.
- `RopeBuffer` — `Buffer` and `TextAnalysisCapable` conformance wrapping `TextRope`, with selection tracking. Drop-in alternative to `MutableStringBuffer` for large documents.
- New `TextRope` library target (zero dependencies), re-exported by `TextBuffer`.

## 0.3.0

### Added

- `TransferableUndoable` buffer wrapper with `OperationLog`-backed undo/redo.
- `snapshot()` and `represent(_:)` for transferring buffer state (content + undo history) between buffers.
- `PuppetUndoManager` for bridging `TransferableUndoable` into AppKit's `UndoManager` system.
- `BufferOperation`, `UndoGroup`, and `OperationLog` value types for inspectable undo history.
- `undoGrouping(actionName:_:)` for grouping multiple mutations into a single undo step.

### Changed

- Renamed `MutableStringBuffer.init(wrapping:)` to `init(copying:)`.
- `UndoGroup` properties are now `internal(set)`.
- Replaced `assert` with `precondition` for overflow check in `resized(by:)`.
- Replaced `try!` and force unwraps with `preconditionFailure` diagnostics.
- Requires macOS 13+ (added platform requirement to Package.swift).

## 0.2.0

Initial public release.
