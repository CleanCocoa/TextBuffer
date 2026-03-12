## 1. Target Setup (TASK-010)

- [ ] 1.1 Add `TextRope` library target (zero dependencies) and `TextRopeTests` test target to `Package.swift`; add `TextRope` as a library product; add `TextRope` dependency to the `TextBuffer` target
- [ ] 1.2 Create `Sources/TextRope/` directory with a placeholder `TextRope.swift` containing `public struct TextRope {}`; verify `swift build --target TextRope` compiles
- [ ] 1.3 Create `Sources/TextBuffer/Exports.swift` with `@_exported import TextRope`; verify TextBuffer consumers can access `TextRope` without explicit import
- [ ] 1.4 Create `Tests/TextRopeTests/` directory with a placeholder test file; verify `swift test --filter TextRopeTests` runs

## 2. Summary Type (TASK-011)

- [ ] 2.1 Implement `TextRope.Summary` in `Sources/TextRope/Summary.swift` — internal struct with `utf8: Int`, `utf16: Int`, `lines: Int` fields; `Sendable`, `Equatable` conformance; `static let zero`
- [ ] 2.2 Implement `Summary.add(_:)` and `Summary.subtract(_:)` mutating methods
- [ ] 2.3 Implement `Summary.of(_ string:) -> Summary` static factory — compute utf8 count, utf16 count, and newline (`\n`) count from the string
- [ ] 2.4 Write `Tests/TextRopeTests/SummaryTests.swift` — test ASCII metrics, multi-byte/emoji metrics (surrogate pairs), empty string, `zero` constant, add/subtract inverse property

## 3. Node Type (TASK-011)

- [ ] 3.1 Implement `TextRope.Node` in `Sources/TextRope/Node.swift` — internal final class (pure Swift, no NSObject); properties: `summary: Summary`, `height: UInt8`, `chunk: String`, `children: ContiguousArray<Node>`
- [ ] 3.2 Define static constants on Node: `maxChildren = 8`, `minChildren = 4`, `maxChunkUTF8 = 2048`, `minChunkUTF8 = 1024`
- [ ] 3.3 Implement `Node.emptyLeaf() -> Node` static factory — returns a leaf with empty chunk, height 0, Summary.zero
- [ ] 3.4 Implement leaf convenience initializer that takes a `String` chunk and computes summary via `Summary.of`
- [ ] 3.5 Implement inner node convenience initializer that takes `ContiguousArray<Node>` children, computes combined summary and height

## 4. COW Infrastructure (TASK-012)

- [ ] 4.1 Implement `Node.shallowCopy() -> Node` — new Node with same summary, height, chunk, and children references (no deep copy)
- [ ] 4.2 Implement `Node.ensureUniqueChild(at:)` — extract→check→write-back pattern using `isKnownUniquelyReferenced`
- [ ] 4.3 Implement `TextRope.ensureUnique()` in `Sources/TextRope/TextRope+COW.swift` — check `isKnownUniquelyReferenced(&root)`, shallow-copy root if shared
- [ ] 4.4 Write `Tests/TextRopeTests/TextRopeCOWTests.swift` — test: unique root is not copied; shared root triggers copy; `ensureUniqueChild` on unique child is no-op; `ensureUniqueChild` on shared child replaces with copy; shallow copy shares children by identity (`===`)

## 5. TextRope Struct & Construction (TASK-013)

- [ ] 5.1 Complete `TextRope` struct in `Sources/TextRope/TextRope.swift` — `nonisolated(unsafe) var root: Node`; `Sendable` conformance; `init()` creates empty leaf root; `isEmpty`, `utf8Count`, `utf16Count` computed from root summary
- [ ] 5.2 Implement `Equatable` conformance for `TextRope` via `content` string comparison
- [ ] 5.3 Implement `init(_ string:)` in `Sources/TextRope/TextRope+Construction.swift` — split string into chunks of `minChunkUTF8...maxChunkUTF8` bytes, respect `\r\n` split invariant, create leaf nodes, build balanced tree bottom-up by grouping in batches of `minChildren...maxChildren`
- [ ] 5.4 Implement `var content: String` in `Sources/TextRope/TextRope+Content.swift` — in-order traversal concatenating all leaf chunks
- [ ] 5.5 Write `Tests/TextRopeTests/TextRopeConstructionTests.swift` — test: empty init round-trip; small string single-leaf; large string multi-leaf with correct chunk sizes; `\r\n` boundary integrity; content round-trip for ASCII, multi-byte, and mixed strings; utf8Count/utf16Count match String properties; Equatable (same content equal, different content not equal)
