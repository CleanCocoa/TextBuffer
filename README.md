# TextBuffer

[![Build Status][build status badge]][build status]
[![Platforms][platforms badge]][platforms]
[![Documentation][documentation badge]][documentation]

Text buffer abstractions to power your text editor, in UI or in memory.

[build status]: https://github.com/CleanCocoa/TextBuffer/actions
[build status badge]: https://github.com/CleanCocoa/TextBuffer/workflows/CI/badge.svg
[platforms]: https://swiftpackageindex.com/CleanCocoa/TextBuffer
[platforms badge]: https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2FCleanCocoa%2FTextBuffer%2Fbadge%3Ftype%3Dplatforms
[documentation]: https://swiftpackageindex.com/CleanCocoa/TextBuffer/main/documentation
[documentation badge]: https://img.shields.io/badge/Documentation-DocC-blue

## Goals

- In-memory text mutations with an API similar to text views.
- Consistent behavior across platforms.


## Approach

We operate on the abstraction of a `Buffer` to perform changes.

This enables usage of the declarative API on multiple buffers at once without having to put the text into a UI component to render.

A `NSTextView` is a buffer. You can use this declarative API to make changes to text views on screen.

You can also use purely in-memory buffers for text mutations of things you don't want to render. This allows you to read multiple files into buffers in your app and use the declarative API to change their contents, while only rendering a single selected file in a text view.

This is harnessed by [`DeclarativeTextKit`](https://github.com/CleanCocoa/DeclarativeTextKit/).


## Installation

Add TextBuffer as a Swift Package Manager dependency:

```swift
dependencies: [
    .package(url: "https://github.com/CleanCocoa/TextBuffer", from: "0.4.0")
]
```


## Key Types

- **`Buffer`** — protocol for reading and mutating text with UTF-16 indexed ranges.
- **`MutableStringBuffer`** — lightweight in-memory `Buffer` backed by `NSMutableString`, for off-screen mutations and tests.
- **`RopeBuffer`** — in-memory `Buffer` backed by `TextRope` (B-tree rope), for large documents with O(log n) edits.
- **`NSTextViewBuffer`** — `Buffer` conformance for `NSTextView`, applying changes directly to the text view.
- **`Undoable`** — wraps a `Buffer` with Foundation `UndoManager` integration for AppKit undo/redo.
- **`TransferableUndoable`** — wraps a `Buffer` with an `OperationLog` for portable undo history; supports `snapshot()` and `represent(_:)` for state transfer.
- **`OperationLog`** — value-type undo history that records `BufferOperation`s grouped into `UndoGroup`s. Inspectable via `log.history`.


## Undo

TextBuffer provides two undo wrappers:

- **`Undoable`** uses Foundation's `UndoManager`. Use this when you need AppKit undo/redo integration (e.g., responding to Edit menu actions in an `NSTextView`-based editor).

- **`TransferableUndoable`** uses an `OperationLog` value type instead. Use this when you need to transfer undo state between buffers — for example, swapping an in-memory buffer's state into a text view. Call `snapshot()` to capture the current content and undo history, and `represent(_:)` to restore it into another `TransferableUndoable`.


## License

Copyright © 2025 Christian Tietze. All rights reserved. Distributed under the MIT License.

[See the LICENSE file.](./LICENSE)
