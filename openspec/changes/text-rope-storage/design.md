## Context

`TextBuffer` is a Swift 6.2 library that defines a `Buffer` protocol for synchronous, `@MainActor`-isolated text editing. All operations accept and return `NSRange` (UTF-16 code unit offsets) and `String`. The current concrete storage, `MutableStringBuffer`, wraps `NSMutableString` and is O(n) for every mutation.

The roadmap calls for a rope backend that is O(log n) per mutation while remaining fully compatible with the `NSRange`-typed protocol boundary. Apple's swift-collections `_RopeModule` / `BigString` was evaluated as a reference implementation and rejected as a direct dependency (unstable SPI, API mismatch, availability constraints), but its architectural patterns — UTF-8 internal storage, multi-count summaries, metric-based tree descent, COW path-copying — directly inform this design.

This change covers **TASK-010 through TASK-018**: the standalone `TextRope` target, core data structures, COW infrastructure, construction, navigation, mutation operations, and the full test suite. Buffer-protocol integration (`RopeBuffer`, TASK-019) and the convergence task (TASK-021) are explicitly out of scope.

## Goals / Non-Goals

**Goals:**

- Deliver a fully tested `TextRope` value type with O(log n) insert, delete, and replace, indexed by UTF-16 offset.
- Store text as UTF-8 (`String` chunks) while caching `utf16` and `lines` counts per subtree node for O(log n) offset translation.
- Provide copy-on-write semantics via `isKnownUniquelyReferenced`; mutation of one copy must not affect other copies.
- Keep `TextRope` in a zero-dependency standalone target (`Sources/TextRope/`) re-exported by `TextBuffer`.
- Ship a comprehensive test suite including a 10K-operation randomised stress test comparing `TextRope` results against equivalent `String` operations.

**Non-Goals:**

- `Buffer` protocol conformance — that is `RopeBuffer` (TASK-019).
- UTF-8-indexed API (`UTF8Range`) — future work; the design deliberately avoids painting into a corner.
- `ManagedBuffer` inline children storage — documented as an upgrade path; not implemented here.
- Line-level API or cursor types — future work.
- Thread safety beyond `@MainActor` serial access — `nonisolated(unsafe)` on `root` is the intentional annotation.

## Decisions

### D1 — UTF-8 internal storage with cached UTF-16 counts (ADR-004)

**Decision:** Store text as Swift `String` (natively UTF-8) in leaf chunks. Each `Node` carries a `Summary` caching `utf8`, `utf16`, and `lines` for its subtree.

**Rationale:** The `Buffer` protocol speaks UTF-16 (`NSRange`), but storing data as UTF-16 would make a future UTF-8 API expensive. UTF-8 storage with a cached `utf16` field per node gives O(log n) `NSRange` translation with no storage duplication. Apple's BigString made the same trade-off for the same reason.

**Alternative rejected:** UTF-16 `[UInt16]` storage — natively maps NSRange but abandons UTF-8 indexing forever and diverges from how Swift `String` stores characters internally.

---

### D2 — `TextRope.Node` as internal `final class` (ADR-005, ADR-006, ADR-007)

**Decision:** `Node` is a non-public `final class` inside `TextRope`. `TextRope` is the public `struct` with value semantics. `Node` must not inherit from `NSObject` — `isKnownUniquelyReferenced` requires a pure Swift class.

**Rationale:** Reference-type nodes enable structural sharing (multiple `TextRope` values share the same subtrees until one mutates). `final` avoids vtable dispatch on hot paths. `isKnownUniquelyReferenced` is the COW primitive; it fails on Objective-C-bridged types.

**Alternative rejected:** Making `Node` itself `Sendable` — it is not safe to share nodes across actors because mutations are not atomic. Safety is provided by `TextRope`'s `@MainActor` call sites and the value-type wrapper.

---

### D3 — `ContiguousArray<Node>` for children storage (ADR-005)

**Decision:** Inner nodes hold `children: ContiguousArray<Node>`. Constants: `maxChildren = 8`, `minChildren = 4`, `maxChunkUTF8 = 2048`, `minChunkUTF8 = 1024`.

**Rationale:** `ContiguousArray` skips Objective-C bridging overhead (unlike plain `Array` on Apple platforms). The "double-COW" cost — copying the array buffer when copying the node — is bounded: with max 8 children and tree depth ≤7, the worst case is ~56 pointer copies per mutation, measured in nanoseconds.

**Upgrade path:** Switch to `ManagedBuffer<Header, Node>` inline storage if profiling identifies the double-allocation as a bottleneck. The node's API is unchanged; only internal storage layout differs.

---

### D4 — Always-rooted design: empty leaf, never `nil` (ADR-006)

**Decision:** `TextRope.root` is a non-optional `Node`. An empty `TextRope` holds an empty leaf node (zero-byte chunk, zero summary). There is no `root: Node?` variant.

**Rationale:** An optional root propagates nil-checks throughout the entire codebase — every recursive function, every property accessor, every COW path. An empty document is a frequent, valid state (new files, cleared buffers). The cost is one trivially small heap allocation per empty rope. `isKnownUniquelyReferenced(&root)` works directly on a non-optional.

---

### D5 — No parent pointers in `Node` (ADR-007)

**Decision:** `Node` has no `parent` reference, weak or unowned.

**Rationale:** `isKnownUniquelyReferenced` returns `false` for any object that has *any* weak reference, even with one strong reference. Weak parent pointers would make COW always copy, destroying structural sharing. All upward traversal uses recursive call stacks: insert returns `(newNode, splitSibling?)`, delete returns `(newNode, isUndersized)`, and the caller handles rebalancing at each level.

---

### D6 — `\r\n` split invariant enforced at chunk-split time

**Decision:** When a chunk is split, if the split point falls between a `\r` byte and a `\n` byte, the split point is adjusted by one byte to keep them together.

**Rationale:** `\r\n` is a single logical line ending. Splitting between them would corrupt line counting and produce incorrect `content(in:)` results for ranges that cross the boundary. Enforcing the invariant at split time (TASK-015) means all other code can assume chunks are never split mid-`\r\n`.

---

### D7 — UTF-16 navigation: tree descent + leaf translation

**Decision:** `findLeaf(utf16Offset:)` descends the tree level by level, subtracting `children[i].summary.utf16` until the target child is identified. At the leaf, the remaining offset is translated to a `String.Index` by walking the chunk's `utf16` view.

**Rationale:** O(log n) tree descent brings navigation to within one leaf. Leaf-level translation is O(chunk_size) but bounded by `maxChunkUTF8 = 2048`, making it a constant factor. No separate "find the leaf" + "find the index" two-pass traversal: the descent and index computation are interleaved in a single top-down pass.

---

### D8 — COW path-copying: single top-down descent

**Decision:** Every mutation (`insert`, `delete`, `replace`) performs a single top-down descent, COW-copying each node along the path before descending into its children. `ensureUnique()` on `TextRope` copies the root; `ensureUniqueChild(at:)` on `Node` uses the extract→check→write-back pattern for `ContiguousArray` elements.

**Rationale:** A "read traversal followed by a second mutation pass" would be simpler to reason about, but it requires descending the tree twice and holding references that prevent the COW check from succeeding on the second pass. Single-pass top-down copying ensures uniqueness before any child is mutated.

## Risks / Trade-offs

**Double-COW cost on `ContiguousArray` children** → Bounded at 56 pointer copies per mutation (8 children × 7 levels). Accepted for v1; mitigated by the documented `ManagedBuffer` upgrade path.

**`nonisolated(unsafe) var root`** → Required because `TextRope` is `Sendable` (value type crossing isolation boundaries) but `Node` is not. Safety depends on callers respecting `@MainActor` isolation. Violation is a data race, not a crash-on-COW issue. Mitigated by the entire `Buffer` protocol being `@MainActor`-isolated.

**Rebalancing complexity in split/merge** → B-tree rebalancing after insert (leaf overflow propagates splits upward) and delete (leaf underflow propagates merges upward) are the highest-complexity code in the module. Mitigated by TASK-018's stress test (10K random operations against a `String` oracle).

**UTF-16 offset within a leaf is O(chunk_size)** → The `utf16` view walk at the leaf level is a tight loop over at most 2048 bytes. For typical ASCII content each UTF-16 unit = 1 byte, so the walk often terminates early. Worst case: a 2048-byte chunk of 4-byte emoji (producing 2 UTF-16 code units each); still < 512 iterations.

**`\r\n` invariant relies on correct split-point adjustment** → If the adjustment is skipped or applied to the wrong boundary (e.g., during cascading splits), line counts will drift. Mitigated by TASK-013's construction tests and TASK-018's `\r\n`-specific stress cases.

## Migration Plan

No migration required — this is a purely additive change. Existing `MutableStringBuffer`, `NSTextViewBuffer`, and `Undoable` are untouched. The `TextRope` target is introduced as a new library product. `TextBuffer` gains a declared dependency on `TextRope` and re-exports it; existing consumers of `TextBuffer` see no API change.

To validate: `swift build` must succeed and `swift test` must pass all new and existing tests.

## Open Questions

- **Rebalancing strategy for deeply-skewed inserts** — the current design uses B-tree split/merge (propagate up the call stack). A weight-balanced or scapegoat variant would be simpler to implement. Chosen approach is consistent with standard B-tree rope literature; revisit only if rebalancing bugs prove hard to fix.
- **`Equatable` conformance** — `TextRope: Equatable` via content comparison (`self.content == other.content`) is sufficient for tests but O(n). If `Equatable` is needed on hot paths, a version counter or hash shortcut should be considered. For now, `Equatable` is provided for testability only.
- **`nonisolated(unsafe)`** — Swift 6.2 requires this annotation for mutable stored properties on `Sendable` types whose element type is not `Sendable`. If `Node` is later made conditionally `Sendable`, this annotation can be removed.
