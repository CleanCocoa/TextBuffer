## ADDED Requirements

### Requirement: TextRope package target exists with zero external dependencies
The `TextRope` Swift target SHALL be declared in `Package.swift` as a standalone library product with no external dependencies. `TextBuffer` SHALL declare a dependency on `TextRope` and re-export it via `@_exported import TextRope` in `Sources/TextBuffer/Exports.swift`. A `TextRopeTests` test target SHALL also be declared, depending only on `TextRope`.

#### Scenario: Package builds cleanly after target addition
- **WHEN** `swift build` is run after adding the `TextRope` target declaration
- **THEN** the build succeeds with no errors and the `TextRope` module is importable

#### Scenario: TextRope re-export is visible to TextBuffer consumers
- **WHEN** a file in `TextBuffer` or `TextBufferTests` imports `TextBuffer`
- **THEN** all public `TextRope` symbols are accessible without a separate `import TextRope`

---

### Requirement: Summary carries utf8, utf16, and lines counts for a subtree
`TextRope.Summary` SHALL be an internal value type (`struct`) with three integer fields: `utf8` (byte count), `utf16` (UTF-16 code unit count), and `lines` (newline count). It SHALL provide:
- A `zero` static constant with all fields set to 0.
- A mutating `add(_:)` method that adds each field of another `Summary`.
- A mutating `subtract(_:)` method that subtracts each field of another `Summary`.
- A static `of(_: String) -> Summary` factory that computes the correct counts for a string chunk without double-scanning.

#### Scenario: Summary.of counts ASCII correctly
- **WHEN** `Summary.of("hello\n")` is called
- **THEN** `utf8 == 6`, `utf16 == 6`, `lines == 1`

#### Scenario: Summary.of counts 4-byte emoji correctly (surrogate pair in UTF-16)
- **WHEN** `Summary.of("😀")` is called on a single emoji
- **THEN** `utf8 == 4`, `utf16 == 2`, `lines == 0`

#### Scenario: Summary arithmetic is consistent
- **WHEN** two Summaries `a` and `b` are added and then `b` is subtracted
- **THEN** the result equals `a` exactly (add/subtract are inverses)

#### Scenario: Summary.zero is the additive identity
- **WHEN** `Summary.zero` is added to any `Summary s`
- **THEN** the result equals `s`

---

### Requirement: Node is an internal final class with chunk, children, summary, and height
`TextRope.Node` SHALL be a non-public `final class` (no `NSObject` ancestry) with:
- `var summary: Summary` — metrics for this node's subtree.
- `var height: UInt8` — 0 for leaves, `max(children.heights) + 1` for inner nodes.
- `var chunk: String` — the text content for leaf nodes; empty string for inner nodes.
- `var children: ContiguousArray<Node>` — child nodes for inner nodes; empty for leaves.
- `static let maxChildren: Int`, `minChildren: Int`, `maxChunkUTF8: Int`, `minChunkUTF8: Int` — tunable constants.
- `func shallowCopy() -> Node` — produces a new node sharing the same `children` array reference and `chunk` value.
- `static func emptyLeaf() -> Node` — produces a leaf with empty chunk and `Summary.zero`.
- `func ensureUniqueChild(at index: Int)` — COW: extracts child, checks `isKnownUniquelyReferenced`, copies if needed, writes back.

#### Scenario: shallowCopy produces an independent node that shares children
- **WHEN** `shallowCopy()` is called on an inner node
- **THEN** the copy and original are different object identities but share the same `children` element references

#### Scenario: emptyLeaf has zero summary
- **WHEN** `Node.emptyLeaf()` is called
- **THEN** `summary == Summary.zero` and `chunk == ""` and `children.isEmpty`

#### Scenario: ensureUniqueChild copies a shared child
- **WHEN** two `TextRope` values share a subtree and `ensureUniqueChild(at:)` is called on the shared inner node
- **THEN** after the call the child at that index is a distinct object from the original child

---

### Requirement: TextRope is an always-rooted public struct with value semantics
`TextRope` SHALL be a public `struct` marked `Sendable` and `Equatable`. It SHALL hold a single non-optional `internal nonisolated(unsafe) var root: Node`. An empty `TextRope` (produced by `init()`) SHALL hold an empty leaf as its root. `TextRope` SHALL never have a `nil` root at any point during its lifetime.

#### Scenario: Default-initialised TextRope is empty
- **WHEN** `TextRope()` is called
- **THEN** `isEmpty == true`, `utf16Count == 0`, `utf8Count == 0`

#### Scenario: isEmpty is a summary check, not a nil check
- **WHEN** `isEmpty` is read on any `TextRope`
- **THEN** it returns `root.summary.utf8 == 0` (root is always present)

---

### Requirement: TextRope COW — mutation of a copy does not affect the original
`TextRope` SHALL implement copy-on-write semantics. After assigning one `TextRope` to another variable:
- Both values share the same root node (verified by identity).
- Mutating one copy SHALL NOT change the content or summary of the other copy.
- Only the nodes along the mutation path are duplicated; unmodified subtrees are shared.

#### Scenario: Assignment shares root identity
- **WHEN** `var b = a` is performed on a non-empty `TextRope a`
- **THEN** `a.root === b.root` immediately after assignment

#### Scenario: Mutation of copy does not affect original
- **WHEN** a `TextRope` `a` is copied to `b` and an insert is performed on `b`
- **THEN** `a.content` is unchanged and `a.utf16Count` equals its pre-copy value

#### Scenario: Only the mutation path is copied
- **WHEN** an insert is performed on one copy of a multi-level rope
- **THEN** nodes not on the mutation path are still shared (identity-equal) between the two copies

---

### Requirement: TextRope construction from a String splits into valid chunks
`TextRope.init(_ string: String)` SHALL build a balanced tree from the input string by splitting it into chunks of at most `Node.maxChunkUTF8` bytes. The `\r\n` split invariant SHALL be enforced: no chunk boundary MAY fall between a `\r` byte and the immediately following `\n` byte.

#### Scenario: Round-trip on empty string
- **WHEN** `TextRope("").content` is computed
- **THEN** the result is `""`

#### Scenario: Round-trip on ASCII content
- **WHEN** `TextRope("hello world").content` is computed
- **THEN** the result equals `"hello world"`

#### Scenario: Round-trip on multi-byte content (emoji)
- **WHEN** `TextRope("😀🎉🚀").content` is computed
- **THEN** the result equals `"😀🎉🚀"` exactly

#### Scenario: Round-trip on content with CRLF sequences
- **WHEN** `TextRope("line1\r\nline2\r\nline3").content` is computed
- **THEN** the result equals the original string and no chunk ends with `\r` when the next chunk starts with `\n`

#### Scenario: utf16Count matches String.utf16.count
- **WHEN** a `TextRope` is constructed from any string `s`
- **THEN** `rope.utf16Count == s.utf16.count`

#### Scenario: Construction of a large string produces a multi-level tree
- **WHEN** a string larger than `maxChunkUTF8` bytes is used to construct a `TextRope`
- **THEN** `root.height > 0` (the tree has at least one inner node)
