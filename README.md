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


## License

Copyright © 2025 Christian Tietze. All rights reserved. Distributed under the MIT License.

[See the LICENSE file.](./LICENSE)
