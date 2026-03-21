# Changelog

## [Unreleased]

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
