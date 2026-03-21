# ``TextBufferTesting``

Test utilities for creating buffers and verifying buffer behavior.

## Overview

TextBufferTesting provides a compact string notation for creating buffers and asserting their state
in unit tests. Use `«guillemets»` to mark a selection and `ˇ` (caron) to mark an insertion point:

```swift
let buffer = try makeBuffer("Hello «World»")
assertBufferState(buffer, "Hello «World»")

var mutable = buffer
try change(buffer: &mutable, to: "Helloˇ World")
assertBufferState(mutable, "Helloˇ World")
```

For verifying undo behavior, compose arrays of ``BufferStep`` values and use the
undo equivalence assertions to confirm that different buffer implementations produce
identical results.

## Topics

### Creating Test Buffers

- ``makeBuffer(_:)``
- ``makeSendableRopeBuffer(_:)``

### Assertions

- ``assertBufferState(_:_:_:file:line:)``
- ``assertUndoEquivalence(initial:steps:file:line:)``
- ``assertSendableUndoEquivalence(initial:steps:file:line:)``

### Test Steps

- ``BufferStep``
- ``applyStep(_:to:)``

### Errors

- ``InvalidBufferStringRepresentation``
