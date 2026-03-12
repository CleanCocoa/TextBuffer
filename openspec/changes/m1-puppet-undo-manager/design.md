## Context

TASK-007 (Phase 4: AppKit Bridge) requires bridging TransferableUndoable's OperationLog-based undo to AppKit's Cmd+Z / Edit menu system. AppKit routes undo actions through the responder chain and queries `NSUndoManager` for menu state. TransferableUndoable (TASK-005) is the prerequisite — it provides the OperationLog-backed undo/redo and the Buffer-conforming decorator that PuppetUndoManager will delegate to.

The design rationale for the subclass approach is fully documented in [ADR-003](../../docs/adr/adr-003--puppet-undo-manager-via-subclass.md). This design doc focuses on implementation shape, boundaries, and integration details.

## Goals / Non-Goals

**Goals:**
- Implement PuppetUndoManager as a stateless NSUndoManager subclass that delegates all queries and actions to TransferableUndoable via PuppetUndoManagerDelegate
- Add `enableSystemUndoIntegration()` to TransferableUndoable with lazy creation and caching semantics
- Block external undo registration to prevent state pollution
- Provide safe degradation when the owner is deallocated (weak reference)
- Document the app-side wiring pattern (allowsUndo=false, delegate return)

**Non-Goals:**
- Implementing the Transfer API (snapshot/represent) — that is TASK-008
- Implementing TransferableUndoable core — that is TASK-005 (prerequisite)
- Handling NSDocument-level undo manager integration (beyond scope)
- Supporting non-AppKit platforms (PuppetUndoManager is macOS-only by nature)

## Decisions

### D1: Stateless puppet with weak owner reference

Per [ADR-003](../../docs/adr/adr-003--puppet-undo-manager-via-subclass.md), PuppetUndoManager holds zero internal undo state. Every override (`canUndo`, `undo()`, `undoActionName`, etc.) delegates to the owner through `PuppetUndoManagerDelegate`. The owner reference is `weak` — if the owning TransferableUndoable is deallocated, queries return safe defaults (`false` for booleans, `""` for strings).

**Why not a proxy-action registration pattern?** ADR-003 evaluated and rejected it: maintaining a parallel proxy stack synchronized with the OperationLog adds complexity and failure modes with no benefit.

### D2: groupsByEvent = false

The puppet sets `groupsByEvent = false` in `init` to prevent AppKit's run-loop-based automatic grouping from interfering. All grouping is managed by OperationLog.

### D3: Block all registration entry points

`NSUndoManager` exposes multiple registration methods:
- `registerUndo(withTarget:selector:object:)` — Objective-C selector-based
- `registerUndo(withTarget:handler:)` — Swift closure-based
- `prepare(withInvocationTarget:)` — NSInvocation-based (returns proxy)

All three MUST be overridden as no-ops to prevent external callers from polluting the puppet's state. The `prepare(withInvocationTarget:)` override returns `self` (the puppet) as a harmless proxy target.

### D4: enableSystemUndoIntegration() is idempotent

Repeated calls return the same PuppetUndoManager instance, stored in TransferableUndoable's `puppetUndoManager` property. The return type is `NSUndoManager` (not `PuppetUndoManager`) so callers don't depend on the concrete subclass.

### D5: PuppetUndoManagerDelegate is internal

The protocol is an implementation detail of the bridge — only TransferableUndoable conforms. It is not public API.

## Risks / Trade-offs

- **[Risk] NSTextView registers undo actions despite allowsUndo=false** → Mitigation: The no-op `registerUndo` overrides are defense-in-depth. Documentation MUST emphasize `allowsUndo = false` as load-bearing. Tests verify that no actions leak through.
- **[Risk] Future AppKit versions add new registration methods** → Mitigation: The puppet's stateless design means unrecognized registration calls are harmless noise at worst. Monitor AppKit release notes.
- **[Risk] Owner deallocation leaves dangling puppet in responder chain** → Mitigation: Weak reference + safe defaults. The puppet degrades to a permanently-disabled undo manager, which is correct behavior when the buffer is gone.
- **[Trade-off] PuppetUndoManager is macOS-only** → Acceptable: it's an AppKit bridge by definition. TransferableUndoable itself is cross-platform; only `enableSystemUndoIntegration()` requires AppKit and should be behind `#if canImport(AppKit)`.
