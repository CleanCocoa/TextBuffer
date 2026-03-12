## Why

TransferableUndoable has undo/redo and the puppet bridge, but lacks the transfer API that is its raison d'être. `snapshot()` and `represent(_:)` are the two methods that enable the single-editor / multi-buffer workflow described in the PRD: saving an editor's state to an in-memory copy and loading a different buffer back in. This change covers TASK-008 and TASK-009 — the final phase of Milestone 1 (Phase 5: Transfer API).

## What Changes

- **Add `snapshot()` to TransferableUndoable** — creates an independent `TransferableUndoable<MutableStringBuffer>` copy with content, selection, and undo history. Value-type log copy ensures independence (ADR-002).
- **Add `represent(_:)` to TransferableUndoable** — replaces content, selection, and undo history entirely from a source buffer. Preconditions `!log.isGrouping`. Discards the receiver's previous undo state.
- **Unit tests for transfer API** — `TransferAPITests.swift` covering snapshot independence, represent state replacement, represent + undo/redo, and precondition violations.
- **Integration tests for end-to-end transfer** — `TransferIntegrationTests.swift` covering transfer-out preserves undo, transfer-in preserves undo, transitivity (A→B→C), snapshot during active puppet bridge, and represent discards previous undo state.

## Capabilities

### New Capabilities
- `buffer-transfer-api`: snapshot() and represent() behavior — creating independent copies, loading state, value-type log copying, preconditions, independence after transfer
- `transfer-integration`: End-to-end transfer scenarios — transfer-out preserves undo, transfer-in preserves undo, transitivity, puppet bridge interaction, undo state replacement

### Modified Capabilities
<!-- No existing capabilities are modified -->

## Impact

- **Files added/modified:**
  - `Sources/TextBuffer/Buffer/TransferableUndoable.swift` — add `snapshot()` and `represent(_:)` methods
  - `Tests/TextBufferTests/TransferAPITests.swift` — new unit test file
  - `Tests/TextBufferTests/TransferIntegrationTests.swift` — new integration test file
- **API surface:** Two new public methods on `TransferableUndoable<Base>`
- **Dependencies:** Requires TASK-005 (TransferableUndoable core), TASK-007 (PuppetUndoManager), TASK-002 (integration test scaffolding) to be complete
