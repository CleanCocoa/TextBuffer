# Undo and Redo

Add undo/redo to your buffers using UndoManager or OperationLog.

## Overview

TextBuffer offers two undo strategies. Choose based on whether you need AppKit `UndoManager` integration
or a portable, `Sendable` undo history.

## UndoManager-Based: Undoable

``Undoable`` is a decorator that wraps any ``Buffer`` and registers inverse actions with Foundation's
`UndoManager`. It integrates directly with AppKit's Edit menu and the responder chain.

```swift
let buffer = MutableStringBuffer("Hello")
let undoable = Undoable(buffer)

undoable.undoGrouping(actionName: "Greet") {
    try! undoable.delete(in: undoable.range)
    try! undoable.insert("Hi, World!")
}
print(buffer.content) // "Hi, World!"

undoable.undo()
print(buffer.content) // "Hello"

undoable.redo()
print(buffer.content) // "Hi, World!"
```

> Warning: You must keep the ``Undoable`` instance alive for undo to work.
> It removes all registered undo actions from its ``Undoable/undoManager`` on deinitialization
> to avoid crashes from dangling `unowned` references.

## OperationLog-Based: TransferableUndoable and SendableRopeBuffer

``OperationLog`` records each mutation as a ``BufferOperation`` value. Undo and redo work by
replaying operations in reverse or forward order. This makes the history inspectable,
serializable, and transferable.

### TransferableUndoable

``TransferableUndoable`` is a decorator like ``Undoable``, but backed by ``OperationLog``
instead of `UndoManager`. It supports snapshotting and state transfer:

```swift
let base = RopeBuffer("Document text")
let buffer = TransferableUndoable(base)

buffer.undoGrouping(actionName: "Edit") {
    try! buffer.replace(range: NSRange(location: 0, length: 8), with: "New")
}

// Snapshot for transfer across actors
let snapshot = buffer.sendableSnapshot()

// Restore from snapshot
buffer.represent(snapshot)

// Bridge to system undo for AppKit menus
let undoManager = buffer.enableSystemUndoIntegration()
myWindow.undoManager = undoManager
```

### SendableRopeBuffer

``SendableRopeBuffer`` is a `Sendable` value type with ``OperationLog`` built in.
No decorator needed — undo/redo is part of the buffer itself:

```swift
var buffer = SendableRopeBuffer("Hello")
try buffer.insert(", World", at: 5)

buffer.undoGrouping(actionName: "Replace") { buf in
    try! buf.delete(in: buf.range)
    try! buf.insert("Goodbye")
}
print(buffer.content) // "Goodbye"

buffer.undo()
print(buffer.content) // "Hello, World"

buffer.redo()
print(buffer.content) // "Goodbye"
```

## Choosing an Undo Strategy

| Strategy | Type | Sendable | AppKit Integration | Snapshots |
|----------|------|----------|--------------------|-----------|
| `UndoManager` | ``Undoable`` | no | built-in | no |
| `OperationLog` | ``TransferableUndoable`` | no (but can snapshot) | via ``TransferableUndoable/enableSystemUndoIntegration()`` | yes |
| `OperationLog` | ``SendableRopeBuffer`` | yes | no | is the snapshot |

Use ``Undoable`` when you already have an `UndoManager` (e.g., document-based apps) and want
zero-configuration AppKit integration.

Use ``TransferableUndoable`` when you need to snapshot buffer state, transfer it across actors,
or want an inspectable operation history while still wrapping a reference-type buffer.

Use ``SendableRopeBuffer`` when you need a fully self-contained, `Sendable` buffer with undo —
for example, in background processing or when the buffer itself crosses isolation boundaries.
