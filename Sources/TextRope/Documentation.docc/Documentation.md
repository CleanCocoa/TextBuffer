# ``TextRope``

A B-tree based rope for efficient text storage and manipulation.

## Overview

`TextRope` is a `Sendable` value type that stores text in a balanced B-tree of chunks,
providing O(log n) insert, delete, and replace operations. This makes it well-suited for
large documents where `NSMutableString`'s O(n) mutations become a bottleneck.

All positions and ranges use UTF-16 code unit offsets (`Int` and half-open `Range<Int>`),
so they translate mechanically to and from the ranges Foundation and AppKit text APIs use.
The struct uses copy-on-write semantics internally. The TextRope module depends on nothing
but the Swift standard library; conveniences that accept Foundation's range type come with
the TextBuffer library.

`TextRope` is used as the backing storage for `RopeBuffer` and `SendableRopeBuffer`
in the TextBuffer library. Import the `TextRope` module directly when you need a standalone
text storage primitive without the buffer protocol API.

```swift
var rope = TextRope("Hello, World!")
rope.insert(" beautiful", at: 6)
print(rope.content) // "Hello, beautiful World!"

rope.delete(in: 0..<7)
print(rope.content) // "beautiful World!"

rope.replace(range: 10..<16, with: "Planet!")
print(rope.content) // "beautiful Planet!"
```

## Topics

### Text Storage

- ``TextRope``
