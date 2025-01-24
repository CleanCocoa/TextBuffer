# ``TextBuffer``

Text buffer abstractions to power your text editor, in UI or in memory.

## Overview

To simulate modifications and insertion point movement or selection changes in text views, you need to create the actual UI component. This is both rather resource intensive and constrained to the `MainActor`.

With in-memory buffers, you get the same behavior, but without the UI overhead.

## Topics

### Buffers

A `Buffer` is an abstraction of textual content and a selection.

- ``Buffer``
- ``MutableStringBuffer``
- ``Undoable``

### Platform-Specific Buffer Adapters

Text Kit's text views behave as buffers, but offer a much wider surface API to perform layout and typesetting. Opposed to these, a `Buffer` is a lightweight API to perform changes like a user would in an interactive text view, which we expose as adapters.

- ``NSTextViewBuffer``

