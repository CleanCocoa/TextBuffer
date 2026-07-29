## Context

This change implements Phase 6 (Rope Foundation) of Milestone 2 — TASK-010 through TASK-013 per TASKS.md. It establishes the `TextRope` target and the foundational types that every subsequent rope operation (insert, delete, replace, navigation) depends on.

The architectural decisions governing this work are already settled:
- **ADR-004**: UTF-8 internal storage with cached UTF-16 counts in summaries
- **ADR-005**: `ContiguousArray<Node>` children with `ManagedBuffer` upgrade path
- **ADR-006**: Always-rooted rope (empty leaf, never nil root)
- **ADR-007**: No parent pointers — path-from-root traversal only

SPEC.md §4.3 provides the complete type definitions. This design extracts the implementation shape for this specific slice.

## Goals / Non-Goals

**Goals:**
- Add `TextRope` as a standalone SPM library target with zero external dependencies
- Implement `Summary` (utf8, utf16, lines) and `Node` (B-tree leaf/inner) internal types
- Implement COW path-copying discipline using `isKnownUniquelyReferenced`
- Implement `TextRope` struct with always-rooted invariant, construction from `String`, and content materialization
- Re-export `TextRope` from `TextBuffer` via `@_exported import`
- Establish test infrastructure in `TextRopeTests`

**Non-Goals:**
- UTF-16 offset navigation (TASK-014)
- Insert, delete, replace mutations (TASK-015–017)
- Node split/merge rebalancing (needed by mutations, not by construction)
- `RopeBuffer` wrapper (TASK-019)
- Performance benchmarking (deferred to TASK-018)

## Decisions

### D1: Package target structure

`TextRope` is a library target with zero dependencies (SPEC.md §3.1). `TextBuffer` depends on `TextRope` and re-exports it. `TextRopeTests` depends only on `TextRope`. This ensures the rope can be used independently of the Buffer protocol and AppKit.

### D2: Node is a pure Swift class — no NSObject

`Node` MUST NOT inherit from `NSObject` or any Objective-C class. `isKnownUniquelyReferenced` only works with pure Swift reference types. The node is `internal final class` — `final` for devirtualization, `internal` because the public API is `TextRope` struct only.

Node is NOT `Sendable`. Thread safety is provided by the `TextRope` value-type wrapper, which is marked `Sendable` with `nonisolated(unsafe) var root: Node` (SPEC.md §4.3).

### D3: COW — extract→check→write-back for array elements

`isKnownUniquelyReferenced` requires a mutable binding. For array elements, the pattern is:
```swift
func ensureUniqueChild(at index: Int) {
    var child = children[index]        // extract
    if !isKnownUniquelyReferenced(&child) {
        child = child.shallowCopy()    // copy
    }
    children[index] = child            // write back
}
```
`shallowCopy()` creates a new Node with the same summary, height, chunk, and children references — it does NOT deep-copy the subtree.

### D4: Chunk splitting respects CR-LF boundaries

When `init(_ string:)` splits a large string into leaf chunks at `maxChunkUTF8` (2048 bytes), if the byte before the split point is `\r` and the byte after is `\n`, the split point shifts by one to keep `\r\n` together. This is the split invariant from SPEC.md §4.3.

### D5: Construction builds a balanced tree bottom-up

`init(_ string:)` splits the input into chunks of `minChunkUTF8...maxChunkUTF8` bytes, creates leaf nodes, then groups them bottom-up in batches of `minChildren...maxChildren` to produce inner nodes, repeating until a single root remains. This guarantees the B-tree invariants from the start.

### D6: Content materialization is O(n) leaf concatenation

`TextRope.content` concatenates all leaf chunks via in-order traversal. `content(in:)` for a UTF-16 range is out of scope for this change (requires UTF-16 navigation from TASK-014).

### D7: File organization

Per SPEC.md §10.3:
- `Sources/TextRope/Summary.swift` — Summary type
- `Sources/TextRope/Node.swift` — Node class with constants, shallowCopy, ensureUniqueChild
- `Sources/TextRope/TextRope.swift` — TextRope struct, init(), isEmpty, utf8Count, utf16Count, Equatable, Sendable
- `Sources/TextRope/TextRope+COW.swift` — ensureUnique()
- `Sources/TextRope/TextRope+Construction.swift` — init(_ string:), chunk splitting, bottom-up tree building
- `Sources/TextRope/TextRope+Content.swift` — var content: String
- `Sources/TextBuffer/Exports.swift` — @_exported import TextRope

## Risks / Trade-offs

- **[Double-COW overhead]** → Per ADR-005, `ContiguousArray` inside a COW node causes O(B×D) pointer copies per mutation. Bounded by B=8, D≤7. Acceptable; `ManagedBuffer` upgrade path documented.
- **[Empty leaf allocation]** → Per ADR-006, every empty `TextRope` allocates one small Node. Negligible for a text editing library.
- **[Chunk size tuning]** → Constants (`maxChunkUTF8=2048`, `minChunkUTF8=1024`, `maxChildren=8`, `minChildren=4`) are from SPEC.md. May need tuning after benchmarks in TASK-018. Constants are static properties on Node, easy to adjust.
- **[No mutations yet]** → This foundation slice deliberately excludes insert/delete/replace. Tests can only verify construction, COW identity behavior, and content round-trips. Mutation correctness is deferred to Phase 7.

## Open Questions

- **`Equatable` conformance cost:** `TextRope: Equatable` is implemented via `self.content == other.content`, which is O(n) — it materializes the entire rope. This is sufficient for tests but unsuitable for hot paths. If `Equatable` is needed on hot paths in future, a version counter or hash shortcut should be considered. For now, `Equatable` is provided for testability only.
- **Rebalancing strategy for deeply-skewed inserts:** The design uses standard B-tree split/merge (propagate up the call stack). A weight-balanced or scapegoat variant would be simpler to implement but less cache-friendly. The chosen approach is consistent with standard B-tree rope literature (xi-editor, Ropey, swift-collections BigString). Revisit only if rebalancing bugs prove hard to fix.
- **`nonisolated(unsafe)` lifecycle:** Swift 6.2 requires this annotation for mutable stored properties on `Sendable` types whose element type is not `Sendable`. If `Node` is later made conditionally `Sendable`, this annotation can be removed. This is a Swift evolution concern, not a design concern.
- **Migration:** No migration required — this is a purely additive change. Existing `MutableStringBuffer`, `NSTextViewBuffer`, and `Undoable` are untouched. `TextBuffer` gains a declared dependency on `TextRope` and re-exports it; existing consumers see no API change.
