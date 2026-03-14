# Changelog

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
