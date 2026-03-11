## Context

`TextBuffer` currently provides `Undoable<Base>`, a decorator that wraps any `Buffer` and routes undo/redo through `NSUndoManager`. This works for single-window editing but breaks the moment undo history must survive a document switch: `NSUndoManager` stores undo actions as closures that capture typed references to a specific `Undoable<Base>` instance. There is no Foundation API to copy, serialize, or retarget those closures.

The goal is a parallel undo implementation — `TransferableUndoable<Base>` — that records mutations as first-class value types so the entire undo stack is a plain Swift struct that can be copied in O(1). A `PuppetUndoManager` bridges this new system back to AppKit's Cmd+Z and Edit menu machinery without AppKit owning any undo state. The existing `Undoable<Base>` stays unchanged and serves as the behavioral oracle for correctness testing via `assertUndoEquivalence`.

**Scope:** TASK-001 through TASK-009 (Milestone 1). Rope, `RopeBuffer`, and convergence are out of scope.

## Goals / Non-Goals

**Goals:**
- Record every `Buffer` mutation as a reversible value-type `BufferOperation`
- Stack operations into nestable `UndoGroup`s inside a value-type `OperationLog`
- Provide `TransferableUndoable<Base>` with identical observable behavior to `Undoable<Base>` (verified by equivalence tests)
- Enable O(1) buffer transfer via `snapshot()` (copy log value) and `represent(_:)` (replace log value)
- Bridge to AppKit Cmd+Z and Edit menu via `PuppetUndoManager` with zero AppKit-owned undo state
- Provide `BufferStep` and `assertUndoEquivalence` for exhaustive drift testing

**Non-Goals:**
- Replacing or deprecating `Undoable<Base>` in this change
- Undo log compaction or memory limits (deferred to a future optimization pass)
- Rope / `RopeBuffer` integration (TASK-021, a separate milestone)
- Persistence or serialization of the undo log
- Concurrent or multi-actor undo (all types are `@MainActor`)

## Decisions

### D-1: OperationLog as a value type (ADR-002)

`OperationLog` is a `struct` containing `[UndoGroup]` (a value-type array) and a `cursor: Int`. A Swift value-type copy of `OperationLog` is independent — mutations to the copy do not affect the original and vice versa. This makes `snapshot()` a two-line function: copy the `MutableStringBuffer`'s content, copy the log. No locking, no weak references, no synchronization.

**Alternative rejected:** Reference-type log with explicit `copy()`. Requires call-site discipline; value semantics enforces independence at the language level.

### D-2: Grouping stack with nested begin/end (ADR-008)

`OperationLog` maintains a `groupingStack: [UndoGroup]`. `beginUndoGroup` pushes; `endUndoGroup` pops. When the stack empties, the top-level group commits to history and truncates the redo tail. Nested groups merge into their parent — the outer group's `selectionBefore` is preserved; the inner group's `actionName` promotes to the parent only if the parent has none. This maps directly onto `TransferableUndoable.undoGrouping(actionName:_:)`, a closure-based API that can be called recursively.

**Alternative rejected:** Flat `begin`/`end` pairs without a stack. Cannot express nested `undoGrouping` calls without additional bookkeeping.

### D-3: Undo and redo as proper inverses (ADR-009)

Each `UndoGroup` stores `selectionBefore: NSRange` (captured at group open) and `selectionAfter: NSRange?` (captured at group close). `undo(on:)` applies inverse operations in reverse order and returns `selectionBefore`; `redo(on:)` reapplies operations in forward order and returns `selectionAfter`. `TransferableUndoable.undo()` / `redo()` explicitly restore the returned selection onto `base.selectedRange`. The invariant — undo followed by redo produces zero observable difference — is mechanically testable and enforced by `assertUndoEquivalence`.

**Alternative rejected:** Redo via replay only (no stored `selectionAfter`). Replay-only selection is fragile when a group contains intermediate cursor moves that the buffer's auto-adjustment logic doesn't reproduce identically.

### D-4: Auto-grouping for single mutations

When a `Buffer` mutation (insert/delete/replace) is called on `TransferableUndoable` outside an explicit `undoGrouping`, the implementation opens a group, records the operation, and immediately closes it. This ensures every mutation is undoable as one step without requiring callers to wrap every call in `undoGrouping`. Calling `record` outside any group is a `preconditionFailure` — it signals a bug in `TransferableUndoable` itself, not a user-input error.

### D-5: PuppetUndoManager as a stateless NSUndoManager subclass (ADR-003)

`PuppetUndoManager` overrides `undo()`, `redo()`, `canUndo`, `canRedo`, `undoActionName`, and `redoActionName` to delegate to `TransferableUndoable` via an internal `PuppetUndoManagerDelegate` protocol. It overrides `registerUndo(withTarget:selector:object:)` as a no-op. The puppet holds a `weak` reference to its owner; if the owner deallocates, all queries return safe defaults (`false`, empty string). No state is stored in the puppet — it is purely a routing layer. `groupsByEvent = false` prevents NSUndoManager from auto-grouping in ways that interfere with our own grouping stack.

**Alternative rejected:** Proxy action registration (push one proxy action per edit group, sync on undo/redo). Requires maintaining the proxy stack in sync with the log across `represent()` calls — more state, more failure modes.

**App-side wiring (documented, not enforced by the library):**
```swift
textView.allowsUndo = false
// NSTextViewDelegate:
func undoManager(for view: NSTextView) -> NSUndoManager? { puppet }
```
`allowsUndo = false` is load-bearing — without it NSTextView registers its own undo actions. The no-op `registerUndo` override is defense-in-depth only.

### D-6: TransferableUndoable conforms to PuppetUndoManagerDelegate

`TransferableUndoable` implements the internal `PuppetUndoManagerDelegate` protocol, forwarding `puppetUndo()` → `self.undo()`, `puppetCanUndo` → `log.canUndo`, etc. This avoids a separate adapter type and keeps the delegation graph simple: puppet → owner (TransferableUndoable) → log.

### D-7: snapshot() and represent() as value-copy operations

`snapshot()` creates a fresh `MutableStringBuffer(wrapping: base)` (copies string content), wraps it in `TransferableUndoable`, then assigns `result.log = self.log` (value copy of the operation log). The two buffers are immediately independent.

`represent(_:)` preconditions `!log.isGrouping` (a document switch mid-group is a programming error), replaces `base` content via `base.replace(range: base.range, with: source.content)`, sets `base.selectedRange = source.selectedRange`, then assigns `self.log = source.log` (value copy). The replace is not recorded as an undoable operation — it is a document switch, not an edit.

### D-8: Dual-buffer equivalence testing as the correctness mechanism

`assertUndoEquivalence` drives the same `[BufferStep]` sequence against both `Undoable<MutableStringBuffer>` (gold standard) and `TransferableUndoable<MutableStringBuffer>` (subject), asserting content and selection equality after every step. The `.group` case maps recursively to `undoGrouping(actionName:) { }` on both. This is the primary guard against behavioral drift — if the operation log diverges from NSUndoManager's semantics in any scenario, the drift test catches it.

## Risks / Trade-offs

**Unbounded log growth** → No compaction in this change. Long editing sessions grow `[UndoGroup]` without limit. Mitigation: deferred to a future pass; log structure (`cursor` + `[UndoGroup]`) already accommodates truncating oldest groups and optionally storing a base snapshot.

**preconditionFailure on inverse operation errors** → If `OperationLog.undo(on:)` applies an inverse that the buffer rejects (e.g., delete a range that no longer exists), the app crashes. This can only happen if the log is corrupt — i.e., if a bug in `TransferableUndoable`'s recording logic recorded an operation inconsistently with what the buffer actually did. The equivalence tests and unit tests guard against this, but production crashes would be hard to diagnose. Mitigation: exhaustive unit tests on `OperationLog` cover all known edge cases; `preconditionFailure` (not `fatalError`) allows overriding in test targets if needed.

**allowsUndo=false is app-side** → The library cannot enforce that consumers set `textView.allowsUndo = false`. If forgotten, NSTextView registers its own undo actions on the puppet, which the puppet's no-op `registerUndo` silently discards. The symptom is that NSTextView content edits are un-undoable via Cmd+Z. Mitigation: clear documentation + AppKit integration pattern in SPEC.md §5.3.

**represent() discards open groups silently** → The `precondition(!log.isGrouping)` crashes rather than silently discards. This is intentional — a document switch mid-group is a programming error. Mitigation: document clearly; if a relaxed behavior is needed later, replace the precondition with `endUndoGroup` + discard.

**Weak owner reference in PuppetUndoManager** → If `TransferableUndoable` is deallocated while the puppet is still installed as the text view's undo manager, all undo/redo calls become no-ops. This is correct behavior (safe degradation) but may be surprising. Mitigation: the normal ownership pattern (EditorController owns both) prevents this.

## Open Questions

- **Log compaction threshold:** Should there be a maximum number of undo groups (e.g., 200) after which oldest groups are silently dropped, or should this remain unbounded for v1? Decision deferred — no user-facing behavior change either way for typical session lengths.
- **Undo across represent():** After `represent(source)`, should `undo()` restore the previous document's state (impossible — it's gone) or do nothing (current behavior — log replaced entirely)? Current behavior is correct; surfacing this to the caller (e.g., a flag on the return value of `represent`) may be useful but is out of scope.
