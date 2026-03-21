# ``TextBuffer``

Text buffer abstractions to power your text editor, in UI or in memory.

## Overview

TextBuffer provides a uniform API for reading, mutating, and selecting text — whether backed by
an `NSMutableString`, a rope, or an `NSTextView`. All buffers share the same operations: access
content, manage a selection or insertion point, and insert, delete, or replace text.

The library defines two parallel protocol hierarchies. ``Buffer`` (which refines ``AsyncBuffer``)
targets reference-type conformers like ``MutableStringBuffer``, ``RopeBuffer``, and
``NSTextViewBuffer``. ``TextBuffer`` targets value types like ``SendableRopeBuffer``.
Both hierarchies expose the same API surface; ``TextAnalysisCapable`` adds word and line range
analysis to either.

## Topics

### Essentials

- <doc:ChoosingABuffer>
- <doc:UndoAndRedo>

### Protocols

- ``Buffer``
- ``TextBuffer``
- ``AsyncBuffer``
- ``TextAnalysisCapable``
- ``BufferRange``
- ``BufferContent``

### In-Memory Buffers

- ``MutableStringBuffer``
- ``RopeBuffer``
- ``SendableRopeBuffer``

### Platform Adapters

- ``NSTextViewBuffer``

### Undo Support

- ``Undoable``
- ``TransferableUndoable``
- ``OperationLog``
- ``UndoGroup``
- ``BufferOperation``

### Error Handling

- ``BufferAccessFailure``
