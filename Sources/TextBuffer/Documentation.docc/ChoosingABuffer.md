# Choosing a Buffer

Pick the right buffer implementation for your use case.

## Overview

The TextBuffer library provides several concrete buffer types that all share the same read-and-mutate API.
They differ in backing storage, value vs. reference semantics, `Sendable` conformance, and built-in undo support.

For most use cases, ``SendableRopeBuffer`` (aliased as `InMemoryBuffer`) is the recommended starting point:
it's a `Sendable` value type with efficient rope-backed storage, built-in undo/redo, and O(log n) mutations
that scale to large documents.

## At a Glance

| Type | Backing | Semantics | Built-in Undo | Sendable | Best for |
|------|---------|-----------|---------------|----------|----------|
| ``SendableRopeBuffer`` | ``TextRope`` | value | ``OperationLog`` | yes | general-purpose in-memory buffer |
| ``MutableStringBuffer`` | `NSMutableString` | reference | no | no | simple tests |
| ``RopeBuffer`` | ``TextRope`` | reference | no | no | reference-type rope without undo |
| ``NSTextViewBuffer`` | `NSTextView` | reference, `@MainActor` | no | no | driving an AppKit text view |

All four conform to ``TextAnalysisCapable``, so you get ``TextAnalysisCapable/wordRange(for:)``
and ``TextAnalysisCapable/lineRange(for:)`` on every buffer.

## The In-Memory Buffer: SendableRopeBuffer

``SendableRopeBuffer`` is the default choice for in-memory text manipulation. It combines:

- **Efficient storage** via ``TextRope`` — O(log n) insert, delete, and replace, even for large documents.
- **Built-in undo/redo** via ``OperationLog`` — no decorator needed.
- **Value semantics and `Sendable`** — safe to pass across actor boundaries.

```swift
var buffer = SendableRopeBuffer("Hello, World!")
try buffer.insert("!", at: 13)
print(buffer.content) // "Hello, World!!"

buffer.undo()
print(buffer.content) // "Hello, World!"
```

For apps that need a reference-type buffer with `UndoManager` integration or snapshot/transfer
capabilities, wrap a ``RopeBuffer`` in ``TransferableUndoable`` (aliased as `EditingBuffer`):

```swift
let editing = TransferableUndoable(RopeBuffer("Document text"))
```

## Other Buffer Types

``MutableStringBuffer`` is backed by `NSMutableString`. It's lightweight and useful in simple tests,
but its O(n) mutations don't scale to large texts. It has no built-in undo — wrap it in
``Undoable`` or ``TransferableUndoable`` if needed.

``RopeBuffer`` gives you rope-backed O(log n) performance as a reference type, but without built-in undo.
Use it when you need a mutable reference-type buffer to wrap in ``Undoable`` or ``TransferableUndoable``.

``NSTextViewBuffer`` adapts an `NSTextView` for use through the buffer API. All mutations go through
`NSTextStorage` wrapped in `beginEditing()`/`endEditing()`. It's `@MainActor`-isolated.

```swift
let textViewBuffer = NSTextViewBuffer(textView: myTextView)
try textViewBuffer.replace(range: textViewBuffer.selectedRange, with: "replacement")
```

## Writing Generic Code

Constrain on ``Buffer`` for reference-type buffers (classes) or ``TextBuffer`` for value-type buffers (structs).
Use ``TextAnalysisCapable`` when you need word or line analysis.

```swift
func wordAtInsertion<B: Buffer>(in buffer: B) throws -> String
where B.Range == NSRange, B.Content == String, B: TextAnalysisCapable {
    let word = try buffer.wordRange(for: buffer.selectedRange)
    return try buffer.content(in: word)
}
```

## Copying Between Buffer Types

Every buffer can be copied into a ``MutableStringBuffer`` or ``RopeBuffer`` via `init(copying:)`:

```swift
let copy = MutableStringBuffer(copying: someBuffer)
let ropeCopy = RopeBuffer(copying: someBuffer)
```

For crossing actor boundaries, ``TransferableUndoable`` provides ``TransferableUndoable/sendableSnapshot()``
to produce a ``SendableRopeBuffer``, and ``TransferableUndoable/represent(_:)-(SendableRopeBuffer)`` to restore
from one:

```swift
// On @MainActor
let snapshot = transferableBuffer.sendableSnapshot()

// On another actor / in a Task
await process(snapshot)

// Back on @MainActor
transferableBuffer.represent(snapshot)
```
