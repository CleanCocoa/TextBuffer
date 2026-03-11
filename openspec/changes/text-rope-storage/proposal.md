## Why

`TextBuffer` currently has no high-performance storage backend. `MutableStringBuffer` wraps an `NSMutableString` and produces O(n) insert and delete for large documents. Introducing a rope data structure provides O(log n) mutations, structural sharing via copy-on-write, and O(1) snapshots — enabling the editor to handle large files without perceptible lag. Because `Buffer` operations are typed in `NSRange` (UTF-16 code units), the rope must navigate by UTF-16 offset without storing the text as UTF-16 internally — UTF-8 storage with cached UTF-16 counts per node satisfies both the ergonomic requirement and the long-term portability goal.

## What Changes

- **New `TextRope` standalone target** (`Sources/TextRope/`) with zero external dependencies.
- **New `TextRope` public struct** — balanced B-tree of UTF-8 `String` chunks; `O(log n)` insert, delete, replace; value semantics via COW.
- **New `TextRope.Node`** — internal `final class`; leaf nodes hold chunks, inner nodes hold `ContiguousArray<Node>` children; no parent pointers.
- **New `TextRope.Summary`** — per-subtree cache of `utf8`, `utf16`, and `lines` counts; enables O(log n) navigation by any encoding unit.
- **COW path-copying** via `isKnownUniquelyReferenced` on `Node`; `ensureUnique()` on `TextRope`; `ensureUniqueChild(at:)` on `Node`.
- **UTF-16 navigation** — `findLeaf(utf16Offset:)` descends the tree using cumulative `summary.utf16`; within a leaf, translates the remainder via the chunk's `utf16` view.
- **`\r\n` split invariant** — chunk-split points are never allowed to fall between a carriage-return and a line-feed byte.
- **New `TextRopeTests` test target** with unit, integration, and stress tests covering construction, COW independence, summary correctness, UTF-16 navigation, insert, delete, replace, and 10K-operation random stress.

This change covers **TASK-010 through TASK-018** (Milestone 2, Phases 6–8). It stops before buffer-protocol integration (`RopeBuffer`, TASK-019) and `TransferableUndoable<RopeBuffer>` convergence (TASK-021), which are separate changes.

## Capabilities

### New Capabilities

- `rope-foundation`: `TextRope` target, package structure, `Summary`, `Node`, always-rooted design, COW infrastructure, leaf construction, and content materialisation.
- `rope-operations`: Core mutation operations — insert, delete, replace — built on UTF-16 offset navigation with correct `\r\n` boundary handling and summary propagation.
- `rope-verification`: Comprehensive test suite validating construction, round-trip content, COW isolation, summary arithmetic, UTF-16 navigation, all mutation edge cases, and a randomised stress test.

### Modified Capabilities

*(none — `Buffer` protocol and existing conformers are unchanged)*

## Impact

- **`Package.swift`** — adds `TextRope` library target and `TextRopeTests` test target; `TextBuffer` gains a `TextRope` dependency; `@_exported import TextRope` added via `Sources/TextBuffer/Exports.swift`.
- **New source files** under `Sources/TextRope/` — `TextRope.swift`, `Summary.swift`, `Node.swift`, `TextRope+COW.swift`, `TextRope+Construction.swift`, `TextRope+Content.swift`, `TextRope+Navigation.swift`, `TextRope+Insert.swift`, `TextRope+Delete.swift`, `TextRope+Replace.swift`, `Node+Split.swift`, `Node+Merge.swift`.
- **New test files** under `Tests/TextRopeTests/` — `SummaryTests.swift`, `TextRopeCOWTests.swift`, `TextRopeConstructionTests.swift`, `TextRopeNavigationTests.swift`, `TextRopeInsertTests.swift`, `TextRopeDeleteTests.swift`, `TextRopeReplaceTests.swift`, `TextRopeStressTests.swift`.
- **No existing source files are modified** (apart from `Package.swift` and the new `Exports.swift`).
- **No public API is removed or changed** — this is purely additive.
