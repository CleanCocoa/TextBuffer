## Why

Milestone 2 requires a standalone `TextRope` target before any rope operations can be built. TASK-010 through TASK-013 (SPEC.md §7.1 Phase 6: Rope Foundation) establish the package structure, core types, COW infrastructure, and leaf construction — the foundation that all subsequent rope tasks (insert, delete, replace, navigation, verification) depend on. This is the critical-path entry point for Milestone 2.

## What Changes

- Add `TextRope` library target to `Package.swift` with zero dependencies; add `TextRopeTests` test target (TASK-010)
- Add `@_exported import TextRope` in `Sources/TextBuffer/Exports.swift` so TextBuffer consumers get rope types automatically (TASK-010)
- Implement `TextRope.Summary` value type with `utf8`, `utf16`, `lines` counts and `of(_:)` factory (TASK-011)
- Implement `TextRope.Node` reference type — B-tree leaf/inner nodes with `ContiguousArray<Node>` children, height, chunk storage, and branching/chunk-size constants (TASK-011)
- Implement COW path-copying via `isKnownUniquelyReferenced` — `TextRope.ensureUnique()`, `Node.shallowCopy()`, `Node.ensureUniqueChild(at:)` (TASK-012)
- Implement `TextRope` struct with always-rooted design (empty leaf, not nil), `init()`, `init(_ string:)` with chunk splitting, and `content` materialization (TASK-013)
- Implement `Equatable` conformance for `TextRope` via content comparison (TASK-013)
- Add `SummaryTests`, `TextRopeCOWTests`, `TextRopeConstructionTests` in `Tests/TextRopeTests/` (TASK-011, 012, 013)

## Capabilities

### New Capabilities
- `rope-target-setup`: TextRope standalone package target with zero dependencies, re-exported by TextBuffer
- `rope-core-types`: Summary metrics, Node B-tree structure, COW path-copying, always-rooted design, construction from String, and content materialization

### Modified Capabilities
<!-- None — this is a new target with no existing specs to modify. -->

## Impact

- **Package.swift**: New `TextRope` library product and target; new `TextRopeTests` test target; `TextBuffer` gains dependency on `TextRope`
- **Sources/TextRope/**: New directory with `TextRope.swift`, `Summary.swift`, `Node.swift`, `TextRope+COW.swift`, `TextRope+Construction.swift`, `TextRope+Content.swift`
- **Sources/TextBuffer/Exports.swift**: New file re-exporting TextRope
- **Tests/TextRopeTests/**: New directory with `SummaryTests.swift`, `TextRopeCOWTests.swift`, `TextRopeConstructionTests.swift`
- **No breaking changes** to existing public API
- **No external dependencies** added
