# Buffer Transfer: Plan

## Concept

An app has **one editor** (`NSTextViewBuffer` wrapped in `Undoable`) and **many in-memory buffers** (`MutableStringBuffer` wrapped in `Undoable`). The user switches between documents. The text view stays; only its content changes.

Two operations from the editor's point of view:

- **Transfer-out**: Snapshot the editor's current state into a new in-memory `Undoable<MutableStringBuffer>`. The in-memory copy has its own independent undo stack that behaves identically.
- **Transfer-in**: Accept an `Undoable<MutableStringBuffer>` and load its state (content, selection, undo history) into the editor.

**"State" = content + selection + undo history.**

After transfer, editor and in-memory copy are **independent**. Undoing on one does not affect the other. But they behave identically — the same undo/redo sequence produces the same results on both.

## What we know works

1. **Drift tests prove behavioral equivalence.** `BufferBehaviorDriftTests` (20+ cases) confirms `MutableStringBuffer` and `NSTextViewBuffer` produce identical content and selection for the same operations.

2. **`Undoable` normalizes undo behavior.** It captures selection state before each operation and restores it on undo, using the same adjustment logic regardless of base buffer type.

## What doesn't work: NSUndoManager for transfer

**Research across 5 alternative approaches confirms: NSUndoManager cannot transfer undo stacks.** Reasons:

- `registerUndo(withTarget:handler:)` uses **unowned references** to specific instances. Closures capture a typed `Undoable<Base>` — you can't retarget them to a different buffer type.
- `Undoable.deinit` calls `removeAllActions(withTarget:)` — deallocating the source destroys its history.
- No Foundation API exists to copy, extract, or retarget undo actions.
- A **proxy/trampoline** pattern (stable intermediary holding a settable buffer reference) fails because: (a) closures are typed to `Undoable<T>`, not type-erased; (b) retargeting makes ALL closures operate on the new buffer, including ones that shouldn't; (c) deinit still destroys actions.

**Production editors don't solve this problem.** CotEditor, CodeEdit, and Runestone all wrap NSUndoManager rather than replacing it. CodeEdit keeps per-file undo managers in a registry, but the undo actions still reference specific view instances — they don't transfer between buffer types.

## The approach: Operation log with reversible deltas

Replace `NSUndoManager` inside `Undoable` with a custom **operation log** that stores mutations as value types.

**Why this wins over alternatives:**

| Approach | Verdict |
|---|---|
| **Operation log (deltas)** | ✅ Operations are values → copyable. O(1) transfer, O(k) undo. |
| **Snapshot-based (memento)** | Viable but memory-heavy: 50 snapshots of a 1MB doc = 50MB. Undo = full content replacement = full NSTextView relayout. |
| **Proxy/trampoline** | ❌ Fatal: closure capture problem, deinit cleanup, type mismatch. |
| **Persistent data structures (ropes)** | ❌ Right idea, wrong time. See "Future: Rope convergence" below. |
| **Buffer-agnostic UndoHistory** | Nearly identical to operation log but with unnecessary indirection. Over-engineered for current needs. |

### How it works

Each mutation records a `BufferOperation` value:

```swift
struct BufferOperation {
    enum Kind {
        case insert(content: String, at: Int)
        case delete(range: NSRange, deletedContent: String)
        case replace(range: NSRange, oldContent: String, newContent: String)
    }
    let kind: Kind
    let selectionBefore: NSRange
}
```

An `OperationLog` holds groups with an undo/redo cursor:

```
[group0, group1, group2, group3]
                              ^cursor
```

- Undo: move cursor back, apply inverse of the group's operations (in reverse order).
- Redo: move cursor forward, reapply the group's operations.
- New edit after undo: truncate the redo tail (standard linear undo).

**Transfer = copy the log.** It's a value type. The copy is independent.

### NSTextView Cmd+Z integration

When the editor uses our operation log instead of NSUndoManager, Cmd+Z still needs to work via the responder chain. Solution: register a **single proxy action** with the system undo manager that delegates to our log:

```swift
// After each operation group, register one action:
systemUndoManager.registerUndo(withTarget: self) { _ in
    self.operationLog.undo(applying: self.base)
}
```

This keeps the Edit menu working without NSUndoManager owning the actual history.

## Execution plan

### Step 1: Write failing high-level tests

Integration-style tests demonstrating the desired transfer behavior. The transfer API is stubbed (compiles but does nothing → assertions fail).

**Test A — Transfer-out preserves undo:**
1. Start with an undoable editor, empty.
2. Insert "Hello", insert ", world" — two undo groups.
3. Transfer-out → get an in-memory `Undoable<MutableStringBuffer>`.
4. Undo on the in-memory copy → assert it shows "Hello" with correct selection.
5. Undo on the editor → assert both are now in the same state.
6. Continue undo/redo on both → lockstep via `assertBufferState`.

**Test B — Transfer-in preserves undo:**
1. Create an in-memory `Undoable<MutableStringBuffer>` with changes on its stack.
2. Transfer-in to the editor.
3. Undo on editor → matches expected previous state.
4. Undo on in-memory copy → both in same state.
5. Redo on both → lockstep.

**Test C — Transitivity:**
1. Start with in-memory buffer, perform changes.
2. Transfer-in to editor.
3. Transfer-out to a new in-memory buffer.
4. All three (original in-memory, editor, new in-memory) undo/redo identically.
5. Proves the type projections are non-destructive.

**Test infrastructure:** Use `assertBufferState(_:_:)`, `makeBuffer(_:)`, and the `textView(_:)` helper from `Helpers.swift`.

### Step 2: Implement content transfer (the easy part)

```swift
destination.replace(range: destination.range, with: source.content)
destination.select(source.selectedRange)
```

Both buffer types handle full-range replacement correctly. After this, tests pass for content/selection but fail for undo history.

### Step 3: Build the operation log (the hard part)

This is the infrastructure change. Replace `NSUndoManager` usage in `Undoable` with `OperationLog`.

- `BufferOperation` — value type recording each mutation + selection state.
- `UndoGroup` — wraps one or more operations as a single undo step.
- `OperationLog` — array of groups + cursor. Supports `undo(on:)` and `redo(on:)` taking any `Buffer`.
- Modify `Undoable.insert`, `.delete`, `.replace` to record into the log instead of calling `undoManager.registerUndo`.
- `undoGrouping(actionName:undoingSelectionChanges:_:)` records into the current group.
- `isRestoringSelection` governs whether selection-only changes are tracked.

**The log is generic over Buffer** — `undo(on:)` applies the inverse operations to whatever buffer you pass. This is what makes transfer work: same log, different buffer.

### Step 4: Wire up transfer API + Cmd+Z bridge

Public API on `Undoable`:

```swift
/// Creates an independent in-memory copy with the same content, selection, and undo history.
func snapshot() -> Undoable<MutableStringBuffer>

/// Replaces content, selection, and undo history with source's state.
func inherit<S>(from source: Undoable<S>)
```

Plus the NSUndoManager bridge for Cmd+Z integration in the editor.

At this point all three tests should pass.

## NSTextView side effects

Any content replacement triggers layout, `processEditing()`, delegate callbacks. This is unavoidable and not a design concern. The existing `wrapAsEditing` already batches correctly.

## Future: Rope convergence

The editor engine spec (`2026-03-07_spec-textbuffer-custom-storage.md`, Phase 6) plans a **rope with COW structural sharing**. A rope makes persistent data structures viable and largely subsumes the operation log for content history:

- **Snapshot = copy root pointer** → O(1), negligible memory (tree nodes are shared between versions).
- **Undo = point to parent version** → no delta application, no replay.
- **Transfer = copy version pointer + version history** → trivially cheap.
- **Memory** → 50 versions of a 1MB doc cost hundreds of KB (shared structure), not 50MB (full copies).

The operation log we build now is the **interim solution**. When the rope arrives, the log's backing store can switch from `[BufferOperation]` to `[RopeVersion]` — version pointers into the rope's history. Selection state (just an `NSRange` per undo point) still needs separate tracking either way.

**The public API stays the same.** `snapshot()`, `inherit(from:)`, and the `OperationLog` interface don't change — only the internal representation does. This means:

1. Build the operation log now → unblocks buffer transfer immediately.
2. Build the rope later (Phase 6) → swap internals, keep API, get O(1) everything.
3. The operation log is not throwaway work — it defines the contract that the rope implementation will fulfill.

## Open questions

- **Selection-only changes**: The current `isRestoringSelection` flag on `Undoable` optionally tracks cursor movements. The operation log needs to decide: are selection-only changes operations in the log, or metadata on adjacent operations?
- **Undo menu action names**: `undoGrouping(actionName:_:)` sets action names on the undo manager. The operation log should store these so the Cmd+Z bridge can display them.
- **Performance**: Long editing sessions grow the log unboundedly. Compaction (base snapshot + recent deltas) is a future optimization, not v1.
- **Scope of NSUndoManager replacement**: `Undoable+NSTextViewBuffer.swift` currently gets the undo manager from the text view's responder chain. The bridge needs to play nice with this — or we change the architecture so the text view's undo manager delegates to our log.
