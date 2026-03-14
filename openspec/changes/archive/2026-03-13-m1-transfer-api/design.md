## Context

TransferableUndoable wraps a Buffer with OperationLog-based undo/redo and PuppetUndoManager integration (TASK-005 through TASK-007). The final Milestone 1 phase adds the transfer API: `snapshot()` and `represent(_:)`. These are the methods that justify TransferableUndoable's existence — they enable the single-editor / multi-buffer workflow where an app saves editor state to in-memory copies and loads different buffers back.

The transfer mechanism relies on OperationLog being a value type (ADR-002). A simple `let copy = log` produces an independent copy with no shared mutable state.

## Goals / Non-Goals

**Goals:**
- Implement `snapshot()` and `represent(_:)` on TransferableUndoable per SPEC.md §4.2
- Unit-test snapshot independence and represent state replacement
- Integration-test end-to-end transfer scenarios: transfer-out, transfer-in, transitivity, puppet bridge interaction, undo state replacement

**Non-Goals:**
- Rope-backed transfer (TASK-021, post-Milestone 2)
- O(1) COW transfer via rope version pointers (future optimization noted in ADR-002)
- Compaction or bounded log growth (future optimization)
- Thread safety beyond @MainActor (single-threaded by design)

## Decisions

### D1: snapshot() returns TransferableUndoable\<MutableStringBuffer\>

Per SPEC.md §4.2, `snapshot()` always returns `TransferableUndoable<MutableStringBuffer>` regardless of the source's `Base` type. This uses `MutableStringBuffer(wrapping:)` to copy content as a String, producing an in-memory buffer suitable for background storage.

The return type is Milestone 1-scoped. Post-rope convergence, this may become generic to leverage TextRope's COW copies (noted in ADR-002). The public signature is stable — only the backing type changes.

**Implementation shape** (from SPEC.md):
```swift
public func snapshot() -> TransferableUndoable<MutableStringBuffer> {
    let copy = MutableStringBuffer(wrapping: base)
    let result = TransferableUndoable<MutableStringBuffer>(copy)
    result.log = self.log  // value type → independent copy
    return result
}
```

### D2: represent(_:) preconditions no open group

Per SPEC.md DA-05, `represent()` calls `precondition(!log.isGrouping)`. A document switch mid-edit-group is a programming error. The precondition fails fast rather than silently discarding partial groups.

`represent()` is not itself undoable — it's a document switch, not an edit. The receiver's previous undo state is entirely discarded and replaced by the source's history.

**Implementation shape** (from SPEC.md):
```swift
public func represent<S: Buffer>(_ source: TransferableUndoable<S>)
where S.Range == NSRange, S.Content == String {
    precondition(!log.isGrouping, "Cannot represent while an undo group is open")
    try? base.replace(range: base.range, with: source.content)
    base.selectedRange = source.selectedRange
    self.log = source.log  // value type → independent copy
}
```

### D3: Value-type log copy guarantees independence

Both `snapshot()` and `represent(_:)` copy the log via simple assignment. Since OperationLog is a value type (ADR-002), this produces a deep independent copy. No shared mutable state exists after transfer. Mutations to either side's log do not affect the other.

### D4: Integration tests validate the PRD workflow

The five integration test scenarios map directly to the PRD's single-editor / multi-buffer workflow:
1. **Transfer-out preserves undo**: Snapshot, then undo on original — the snapshot retains its independent history
2. **Transfer-in preserves undo**: Represent a source, then undo on the receiver — undoes the source's history
3. **Transitivity**: A→B→C transfer chain — each step produces independent copies
4. **Puppet bridge interaction**: Snapshot while PuppetUndoManager is active — both continue to work
5. **Undo state replacement**: Represent discards the receiver's prior undo history entirely

## Risks / Trade-offs

- **[O(n) content copy]** → `snapshot()` copies the full buffer content via `MutableStringBuffer(wrapping:)`. Acceptable for Milestone 1; rope COW will reduce to O(1) in Milestone 2.
- **[Unbounded log growth]** → Neither `snapshot()` nor `represent()` address log compaction. Long sessions accumulate history without limit. Mitigation: compaction is a separate future concern (noted in ADR-002).
- **[represent() during puppet bridge]** → After `represent()`, the PuppetUndoManager's internal NSUndoManager state may be stale (it holds registered undo actions from the previous document). The puppet must be resilient to this — its undo/redo delegates to the log, so stale NSUndoManager actions just need to not crash. This is tested in the integration suite.

## Open Questions

- **Undo across represent():** After `represent(source)`, `undo()` replays the source's prior history — it does not restore the receiver's previous document. The previous state is entirely gone (the log was replaced). This is correct behavior, but surfacing it to the caller (e.g., a boolean return or a flag on `represent`) may be useful in future. Out of scope for this change, but worth noting for API evolution.
- **O(1) snapshot via rope COW:** Post-Milestone 2, `snapshot()` could leverage `TextRope`'s structural sharing to avoid the O(n) content copy — the `MutableStringBuffer(wrapping:)` call would be replaced by a rope value copy (COW, effectively O(1)). The public signature is stable; only the backing type changes.
