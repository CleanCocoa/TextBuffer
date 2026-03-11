# Solution Specification: TextBuffer — Operation Log & Rope

**Version:** 1.0
**Date:** 2026-03-11
**Author:** Solution Architect (AI-Assisted)
**Status:** Draft
**Source Requirements:** plan.md, 2026-03-07_spec-textbuffer-custom-storage.md

---

## 1. Executive Summary

TextBuffer is a Swift library providing a `Buffer` protocol for text editing with two existing conformers (`MutableStringBuffer`, `NSTextViewBuffer`) and an `Undoable<Base>` decorator backed by `NSUndoManager`. This spec adds two milestones:

**Milestone 1 (Operation Log):** A value-type `OperationLog` that records reversible deltas, powering a new `TransferableUndoable<Base>` decorator. Because the log is a plain value type, buffer transfer (copying content + selection + undo history between editor and in-memory buffers) becomes a simple value copy. A `PuppetUndoManager` subclass bridges to AppKit's Cmd+Z and Edit menu. The existing `Undoable<Base>` remains as the behavioral gold standard for equivalence testing.

**Milestone 2 (Rope):** A `TextRope` data structure in a standalone package target — a balanced B-tree of UTF-8 string chunks with O(log n) insert/delete/replace. UTF-16 counts cached in node summaries enable O(log n) `NSRange` translation. COW via `isKnownUniquelyReferenced` on reference-type nodes. A `RopeBuffer` wrapper adds `Buffer` conformance.

The milestones are structurally independent and can be developed in parallel branches. They converge when `TransferableUndoable<RopeBuffer>` is verified.

---

## 2. Architecture Overview

### 2.1 Architecture Style

Modular library — single Swift package, multiple targets. No services, no deployment infrastructure. All interactions are synchronous, in-process, `@MainActor`-isolated method calls.

### 2.2 System Component Map

```
TextBuffer (library target, depends on TextRope)
├── Buffer protocol + existing conformers
│   ├── MutableStringBuffer              (unchanged)
│   ├── NSTextViewBuffer                 (unchanged)
│   └── RopeBuffer                       [Milestone 2] (new, wraps TextRope)
│
├── Undo infrastructure
│   ├── Undoable<Base>                   (unchanged, NSUndoManager-backed)
│   ├── OperationLog                     [Milestone 1] (new, value type)
│   ├── TransferableUndoable<Base>       [Milestone 1] (new, OperationLog-backed)
│   └── PuppetUndoManager               [Milestone 1] (new, NSUndoManager subclass)
│
└── Transfer API
    ├── snapshot()                       [Milestone 1] (on TransferableUndoable)
    └── represent(_:)                    [Milestone 1] (on TransferableUndoable)

TextRope (library target, zero dependencies)
├── TextRope                             [Milestone 2] (public struct)
├── TextRope.Node                        [Milestone 2] (internal final class)
└── TextRope.Summary                     [Milestone 2] (internal struct)

TextBufferTesting (library target, depends on TextBuffer)
├── assertBufferState                    (existing)
├── makeBuffer                           (existing)
├── BufferStep enum                      [Milestone 1] (new)
└── assertUndoEquivalence                [Milestone 1] (new)

Tests
├── TextBufferTests                      (depends on TextBuffer, TextBufferTesting)
│   ├── Existing tests                   (unchanged)
│   ├── OperationLog unit tests          [Milestone 1]
│   ├── TransferableUndoable tests       [Milestone 1]
│   ├── Undo equivalence drift tests     [Milestone 1]
│   ├── Transfer integration tests       [Milestone 1]
│   ├── RopeBuffer drift tests           [Milestone 2]
│   └── Rope+Transfer integration tests  [Milestone 2]
└── TextRopeTests                        (depends on TextRope)
    └── TextRope unit + stress tests     [Milestone 2]
```

### 2.3 Milestone Independence

Milestone 2 (Rope) has zero dependency on Milestone 1 (Operation Log). They share no types until the convergence task (TASK-021). This means:

- Two worktrees / branches can develop simultaneously
- The rope works with the existing `Undoable` as well
- Either milestone can ship independently

---

## 3. Technology Stack

| Layer | Technology | Version | Justification |
|---|---|---|---|
| Language | Swift | 6.2 | Already in use (swift-tools-version: 6.2) |
| Platform | macOS (AppKit) | — | NSTextView integration; MutableStringBuffer is cross-platform |
| Package manager | Swift Package Manager | — | Already in use |
| Testing | XCTest | — | Already in use; drift testing pattern established |
| Concurrency | @MainActor isolation | — | Matches existing Buffer protocol; COW safe under serial access |

No external dependencies. No new packages.

### 3.1 Package Structure

```swift
let package = Package(
    name: "TextBuffer",
    products: [
        .library(name: "TextBuffer", targets: ["TextBuffer"]),
        .library(name: "TextRope", targets: ["TextRope"]),
        .library(name: "TextBufferTesting", targets: ["TextBufferTesting"]),
    ],
    targets: [
        .target(name: "TextRope"),
        .target(name: "TextBuffer", dependencies: ["TextRope"]),
        .target(name: "TextBufferTesting", dependencies: ["TextBuffer"]),
        .testTarget(name: "TextBufferTests",
                    dependencies: ["TextBuffer", "TextBufferTesting"]),
        .testTarget(name: "TextRopeTests",
                    dependencies: ["TextRope"]),
    ]
)
```

TextBuffer re-exports TextRope:
```swift
// Sources/TextBuffer/Exports.swift
@_exported import TextRope
```

---

## 4. Data Architecture

### 4.1 Type Relationships

```
[OperationLog] 1──M [UndoGroup] 1──M [BufferOperation]

[TransferableUndoable<Base>] 1──1 [OperationLog]
                             1──1 [Base: Buffer]
                             0──1 [PuppetUndoManager]

[PuppetUndoManager] ──weak──► [PuppetUndoManagerDelegate]
                              (TransferableUndoable conforms)

[TextRope] 1──1 [Node]  (root)
[Node] 0──M [Node]      (children, inner nodes)
[Node] 1──1 [Summary]

[RopeBuffer] 1──1 [TextRope]
```

### 4.2 Milestone 1 Types

#### BufferOperation

```swift
/// A single, reversible mutation recorded as a value type.
public struct BufferOperation: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        /// Text was inserted. Inverse: delete the range it occupies.
        case insert(content: String, at: Int)

        /// Text was deleted. Inverse: re-insert at the same location.
        case delete(range: NSRange, deletedContent: String)

        /// Text was replaced. Inverse: replace back with oldContent.
        case replace(range: NSRange, oldContent: String, newContent: String)
    }

    public let kind: Kind
}
```

#### UndoGroup

```swift
/// A group of operations that undo/redo together as one step.
public struct UndoGroup: Sendable, Equatable {
    /// Operations in this group, in the order they were performed.
    public internal(set) var operations: [BufferOperation]

    /// Selection state before this group was executed. Restored on undo.
    public let selectionBefore: NSRange

    /// Selection state after this group was executed. Restored on redo.
    public var selectionAfter: NSRange?

    /// User-facing action name for the Edit menu.
    public var actionName: String?
}
```

#### OperationLog

```swift
/// A value-type undo/redo stack of operation groups.
///
/// Maintains two structures:
/// - history + cursor: completed top-level groups for undo/redo
/// - groupingStack: open groups during recording (recursive nesting)
///
/// The grouping mechanism is a stack. beginUndoGroup pushes, endUndoGroup
/// pops. Nested groups merge into their parent. Only the top-level group
/// closing commits to undo history.
public struct OperationLog: Sendable, Equatable {
    /// Completed undo groups.
    /// history[0..<cursor] = undoable, history[cursor...] = redoable.
    private var history: [UndoGroup]
    private var cursor: Int

    /// Stack of open groups. Empty when no grouping is active.
    private var groupingStack: [UndoGroup]

    public init()

    /// Whether we're inside an open undo group.
    public var isGrouping: Bool

    // MARK: - Recording

    /// Open a new undo group. Can be nested.
    public mutating func beginUndoGroup(
        selectionBefore: NSRange,
        actionName: String? = nil
    )

    /// Close the current undo group.
    /// Nested: operations merge into parent.
    /// Top-level: commits to history, truncates redo tail.
    public mutating func endUndoGroup(selectionAfter: NSRange)

    /// Record an operation into the current open group.
    public mutating func record(_ operation: BufferOperation)

    // MARK: - Undo / Redo

    public var canUndo: Bool
    public var canRedo: Bool
    public var undoableCount: Int
    public var undoActionName: String?
    public var redoActionName: String?
    public func actionName(at index: Int) -> String?

    /// Undo most recent group. Returns selectionBefore to restore.
    @discardableResult
    public mutating func undo<B: Buffer>(on buffer: B) -> NSRange?
    where B.Range == NSRange, B.Content == String

    /// Redo next group. Returns selectionAfter to restore.
    @discardableResult
    public mutating func redo<B: Buffer>(on buffer: B) -> NSRange?
    where B.Range == NSRange, B.Content == String
}
```

**Undo mechanics:** `undo(on:)` moves cursor back, applies inverse of the group's operations in reverse order on the buffer, returns `selectionBefore`. `redo(on:)` moves cursor forward, reapplies operations in forward order, returns `selectionAfter`. Both undo and redo restore exact selection state — they are proper inverses. Undo followed by redo (or vice versa) produces no observable difference.

**Inverse operations fail with preconditionFailure.** If the log is correct and the buffer started in the expected state, inverse operations cannot fail. A failure means a bug in the recording logic.

**Grouping stack semantics:**
- `beginUndoGroup` pushes a new group onto the stack
- `endUndoGroup` pops the top group
  - If the stack is now empty → top-level group, commit to history, truncate redo tail
  - If the stack is non-empty → nested group, merge operations into parent. Parent keeps its selectionBefore; promote action name if parent has none.
- `record` appends to the top of the stack
- Calling `record` outside a group is a precondition failure

#### TransferableUndoable\<Base\>

```swift
/// Decorator of any Buffer to add undo/redo via OperationLog.
/// Supports buffer transfer: snapshot() creates an independent copy,
/// represent(_:) loads another buffer's complete state.
@MainActor
public final class TransferableUndoable<Base: Buffer>: Buffer
where Base.Range == NSRange, Base.Content == String {
    public typealias Range = NSRange
    public typealias Content = String

    private let base: Base
    internal var log: OperationLog
    private var puppetUndoManager: PuppetUndoManager?

    public init(_ base: Base)

    // MARK: - Buffer conformance
    // All mutations: auto-group if not already grouping,
    // capture old content, delegate to base, record to log.

    public var content: String
    public var range: NSRange
    public var selectedRange: NSRange { get set }
    public func content(in range: NSRange) throws(BufferAccessFailure) -> String
    public func unsafeCharacter(at location: Int) -> String
    public func insert(_ content: String, at location: Int) throws(BufferAccessFailure)
    public func delete(in deletedRange: NSRange) throws(BufferAccessFailure)
    public func replace(range: NSRange, with content: String) throws(BufferAccessFailure)
    public func modifying<T>(affectedRange: NSRange, _ block: () -> T) throws(BufferAccessFailure) -> T

    // MARK: - Undo grouping

    /// Group multiple mutations as one undo step. Nestable.
    public func undoGrouping<T>(
        actionName: String? = nil,
        _ block: () throws -> T
    ) rethrows -> T

    // MARK: - Undo / Redo

    public var canUndo: Bool
    public var canRedo: Bool
    public func undo()
    public func redo()

    // MARK: - Transfer

    /// Creates an independent in-memory copy with the same content,
    /// selection, and undo history. Both original and copy are
    /// independent afterwards.
    public func snapshot() -> TransferableUndoable<MutableStringBuffer>

    /// Replaces content, selection, and undo history entirely with
    /// source's state. Previous state is discarded. This is a
    /// document switch, not an edit — it is not itself undoable.
    /// Precondition: no undo group is currently open.
    public func represent<S: Buffer>(
        _ source: TransferableUndoable<S>
    ) where S.Range == NSRange, S.Content == String

    // MARK: - AppKit integration

    /// Returns a PuppetUndoManager for Cmd+Z / Edit menu integration.
    /// Install via NSTextViewDelegate.undoManager(for:) and set
    /// textView.allowsUndo = false.
    public func enableSystemUndoIntegration() -> NSUndoManager
}
```

**Mutation recording pattern (each insert/delete/replace):**

```swift
public func insert(_ content: String, at location: Int) throws(BufferAccessFailure) {
    let autoGroup = !log.isGrouping
    if autoGroup {
        log.beginUndoGroup(selectionBefore: base.selectedRange)
    }
    try base.insert(content, at: location)
    log.record(.init(kind: .insert(content: content, at: location)))
    if autoGroup {
        log.endUndoGroup(selectionAfter: base.selectedRange)
    }
}
```

**Undo grouping (nestable):**

```swift
public func undoGrouping<T>(actionName: String? = nil, _ block: () throws -> T) rethrows -> T {
    log.beginUndoGroup(selectionBefore: base.selectedRange, actionName: actionName)
    let result = try block()
    log.endUndoGroup(selectionAfter: base.selectedRange)
    return result
}
```

**Transfer — snapshot:**

```swift
public func snapshot() -> TransferableUndoable<MutableStringBuffer> {
    let copy = MutableStringBuffer(wrapping: base)
    let result = TransferableUndoable<MutableStringBuffer>(copy)
    result.log = self.log  // value type → independent copy
    return result
}
```

**Transfer — represent:**

```swift
public func represent<S: Buffer>(_ source: TransferableUndoable<S>)
where S.Range == NSRange, S.Content == String {
    precondition(!log.isGrouping, "Cannot represent while an undo group is open")
    try? base.replace(range: base.range, with: source.content)
    base.selectedRange = source.selectedRange
    self.log = source.log  // value type → independent copy
}
```

#### PuppetUndoManager

```swift
/// NSUndoManager subclass that delegates undo/redo to an OperationLog
/// via TransferableUndoable. Installed via
/// NSTextViewDelegate.undoManager(for:).
///
/// App-side wiring:
///   textView.allowsUndo = false
///   delegate.undoManager(for:) → puppet
@MainActor
public final class PuppetUndoManager: NSUndoManager {
    private weak var owner: (any PuppetUndoManagerDelegate)?

    init(owner: any PuppetUndoManagerDelegate) {
        self.owner = owner
        super.init()
        self.groupsByEvent = false
    }

    public override func undo() { owner?.puppetUndo() }
    public override func redo() { owner?.puppetRedo() }
    public override var canUndo: Bool { owner?.puppetCanUndo ?? false }
    public override var canRedo: Bool { owner?.puppetCanRedo ?? false }
    public override var undoActionName: String { owner?.puppetUndoActionName ?? "" }
    public override var redoActionName: String { owner?.puppetRedoActionName ?? "" }

    // Prevent external undo registration
    public override func registerUndo(
        withTarget target: Any, selector: Selector, object anObject: Any?
    ) { /* no-op */ }
}

@MainActor
internal protocol PuppetUndoManagerDelegate: AnyObject {
    func puppetUndo()
    func puppetRedo()
    var puppetCanUndo: Bool { get }
    var puppetCanRedo: Bool { get }
    var puppetUndoActionName: String { get }
    var puppetRedoActionName: String { get }
}

// TransferableUndoable conforms to PuppetUndoManagerDelegate
```

**Cmd+Z flow:**

```
User presses Cmd+Z
  → AppKit sends undo: action up responder chain
  → NSResponder.undo: calls self.undoManager?.undo()
  → NSTextView asks delegate for undoManager → PuppetUndoManager
  → PuppetUndoManager.undo() calls owner.puppetUndo()
  → TransferableUndoable.undo()
  → OperationLog.undo(on: base) applies inverse operations
  → base buffer content + selection restored
```

**Edit menu state:**

```
Edit > Undo [action name]
  → validateUserInterfaceItem reads puppet.canUndo + puppet.undoMenuItemTitle
  → PuppetUndoManager.canUndo → owner.puppetCanUndo → log.canUndo
  → PuppetUndoManager.undoActionName → owner.puppetUndoActionName → log.undoActionName
  → Menu item enabled/disabled and titled correctly
```

### 4.3 Milestone 2 Types

#### TextRope.Summary

```swift
extension TextRope {
    /// Cached metrics per subtree.
    internal struct Summary: Sendable, Equatable {
        var utf8: Int    // byte count
        var utf16: Int   // UTF-16 code unit count
        var lines: Int   // newline count

        static let zero = Summary(utf8: 0, utf16: 0, lines: 0)

        mutating func add(_ other: Summary) {
            utf8 += other.utf8
            utf16 += other.utf16
            lines += other.lines
        }

        mutating func subtract(_ other: Summary) {
            utf8 -= other.utf8
            utf16 -= other.utf16
            lines -= other.lines
        }

        /// Compute summary for a string chunk.
        static func of(_ string: String) -> Summary {
            var utf16 = 0
            var lines = 0
            string.withUTF8 { buffer in
                utf16 = string.utf16.count
                for byte in buffer {
                    if byte == UInt8(ascii: "\n") { lines += 1 }
                }
            }
            return Summary(utf8: string.utf8.count, utf16: utf16, lines: lines)
        }
    }
}
```

**Design note:** Caching both utf8 and utf16 counts per node follows Apple's BigString/Rope pattern. This enables O(log n) translation between byte offsets and UTF-16 offsets (for NSRange compatibility) without scanning leaf content during navigation.

Line count is included from day one — it's ~5 lines of code to count `\n` during chunk construction and enables O(log n) line-to-offset lookup for future `LineIndex` integration.

#### TextRope.Node

```swift
extension TextRope {
    /// B-tree node. Leaf nodes hold string chunks, inner nodes hold children.
    /// Reference type with COW via isKnownUniquelyReferenced.
    /// NOT Sendable — safety is provided by the TextRope struct wrapper.
    /// Must remain pure Swift (no NSObject ancestry) for
    /// isKnownUniquelyReferenced to work.
    internal final class Node {
        var summary: Summary
        var height: UInt8

        // Leaf: the text chunk; Inner: empty string
        var chunk: String

        // Leaf: empty; Inner: child nodes
        var children: ContiguousArray<Node>

        // MARK: - Constants (tunable)
        static let maxChildren = 8
        static let minChildren = 4
        static let maxChunkUTF8 = 2048
        static let minChunkUTF8 = 1024

        /// Shallow copy: new node, shares children/chunk references.
        func shallowCopy() -> Node

        /// Factory for an empty leaf.
        static func emptyLeaf() -> Node

        /// COW: ensure child at index is uniquely referenced.
        /// Uses extract → check → write back pattern.
        func ensureUniqueChild(at index: Int) {
            var child = children[index]
            if !isKnownUniquelyReferenced(&child) {
                child = child.shallowCopy()
            }
            children[index] = child
        }
    }
}
```

**COW path-copying discipline:** Every mutation must copy-on-write all nodes along the mutation path, not just the root. The pattern is a single top-down descent — no read-only traversal followed by a second mutation pass.

**Split invariant:** Never split a chunk between `\r` and `\n`. When finding a split point, if the byte before the split is `\r` and the byte after is `\n`, adjust the split point by one.

**No parent pointers.** Weak parent references break `isKnownUniquelyReferenced` (always returns false with any weak reference). Use path-from-root traversal only.

#### TextRope

```swift
/// A balanced tree of string chunks for efficient text editing.
/// O(log n) insert, delete, replace. Value semantics with COW.
public struct TextRope: Sendable, Equatable {
    /// Always-rooted: empty rope has an empty leaf, not nil.
    internal nonisolated(unsafe) var root: Node

    public init()                    // empty rope (empty leaf)
    public init(_ string: String)    // splits into chunks, builds tree

    public var isEmpty: Bool
    public var utf16Count: Int       // root.summary.utf16
    public var utf8Count: Int        // root.summary.utf8

    /// Full content. O(n) — concatenates all leaves.
    public var content: String

    /// Content in a UTF-16 range. O(log n + k).
    public func content(in utf16Range: NSRange) -> String

    /// Insert at UTF-16 offset. O(log n).
    public mutating func insert(_ string: String, at utf16Offset: Int)

    /// Delete a UTF-16 range. O(log n).
    public mutating func delete(in utf16Range: NSRange)

    /// Replace a UTF-16 range. O(log n).
    public mutating func replace(range utf16Range: NSRange, with string: String)

    // MARK: - COW
    internal mutating func ensureUnique() {
        if !isKnownUniquelyReferenced(&root) {
            root = root.shallowCopy()
        }
    }
}
```

**UTF-16 navigation:** To find "UTF-16 offset X", walk the tree: at each inner node, accumulate `children[0..<i].summary.utf16` to find which child contains offset X. At the leaf, translate the remaining UTF-16 offset to a `String.Index` by walking the chunk's `utf16` view. Leaf-level translation is O(chunk_size), bounded by `maxChunkUTF8`.

#### RopeBuffer

```swift
/// Buffer conformer wrapping TextRope. Adds selection tracking.
/// Same pattern as MutableStringBuffer wraps NSMutableString.
public final class RopeBuffer: Buffer, TextAnalysisCapable {
    public typealias Range = NSRange
    public typealias Content = String

    internal var rope: TextRope
    public var selectedRange: NSRange

    public init(_ content: String = "")

    public var content: String { rope.content }
    public var range: NSRange { NSRange(location: 0, length: rope.utf16Count) }

    // insert, delete, replace: delegate to rope + adjust selection
    // Selection adjustment logic identical to MutableStringBuffer:
    // - insert before/at selection: shift selection right
    // - delete overlapping selection: subtract
    // - replace: subtract then shift
}
```

### 4.4 Testing Infrastructure

#### BufferStep

```swift
/// An operation step for equivalence testing.
public enum BufferStep {
    case insert(content: String, at: Int)
    case delete(range: NSRange)
    case replace(range: NSRange, with: String)
    case select(NSRange)
    case undo
    case redo
    case group(actionName: String?, steps: [BufferStep])
}
```

#### assertUndoEquivalence

```swift
/// Runs identical steps on an Undoable (gold standard) and a
/// TransferableUndoable (subject), asserting identical content +
/// selection after every step.
@MainActor
public func assertUndoEquivalence(
    reference: Undoable<MutableStringBuffer>,
    subject: TransferableUndoable<MutableStringBuffer>,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
)
```

The function iterates steps, applying each to both buffers via static dispatch (two lines per step, one for each buffer), and asserts content + selection equality after each step. The `.group` case maps to `undoGrouping(actionName:) { }` on both types, with inner steps applied recursively.

Convenience wrapper creates both buffers from an initial string:

```swift
@MainActor
public func assertUndoEquivalence(
    initial: String,
    steps: [BufferStep],
    file: StaticString = #filePath,
    line: UInt = #line
)
```

---

## 5. API Specification

### 5.1 Public API Surface — Milestone 1

**New types:**

| Type | Module | Visibility |
|---|---|---|
| `BufferOperation` | TextBuffer | public |
| `BufferOperation.Kind` | TextBuffer | public |
| `UndoGroup` | TextBuffer | public |
| `OperationLog` | TextBuffer | public |
| `TransferableUndoable<Base>` | TextBuffer | public |
| `PuppetUndoManager` | TextBuffer | public |
| `PuppetUndoManagerDelegate` | TextBuffer | internal |

**TransferableUndoable key methods:**

| Method | Description |
|---|---|
| `init(_ base: Base)` | Wrap a buffer with operation-log undo |
| `undoGrouping(actionName:_:)` | Group mutations as one undo step (nestable) |
| `undo()` | Undo most recent group, restore selectionBefore |
| `redo()` | Redo next group, restore selectionAfter |
| `snapshot()` | Copy content + selection + undo history to new in-memory buffer |
| `represent(_:)` | Replace content + selection + undo history from source |
| `enableSystemUndoIntegration()` | Return PuppetUndoManager for AppKit wiring |

**New testing types (TextBufferTesting):**

| Type | Visibility |
|---|---|
| `BufferStep` | public |
| `assertUndoEquivalence(reference:subject:steps:)` | public |
| `assertUndoEquivalence(initial:steps:)` | public |

### 5.2 Public API Surface — Milestone 2

**New types:**

| Type | Module | Visibility |
|---|---|---|
| `TextRope` | TextRope | public |
| `TextRope.Summary` | TextRope | internal |
| `TextRope.Node` | TextRope | internal |
| `RopeBuffer` | TextBuffer | public |

**TextRope key methods:**

| Method | Description |
|---|---|
| `init()` | Empty rope |
| `init(_ string: String)` | Build rope from string |
| `var content: String` | Full text, O(n) |
| `func content(in: NSRange) -> String` | Substring, O(log n + k) |
| `mutating func insert(_:at:)` | Insert at UTF-16 offset, O(log n) |
| `mutating func delete(in:)` | Delete UTF-16 range, O(log n) |
| `mutating func replace(range:with:)` | Replace UTF-16 range, O(log n) |
| `var utf16Count: Int` | Total UTF-16 length, O(1) |
| `var utf8Count: Int` | Total UTF-8 length, O(1) |

### 5.3 AppKit Integration Pattern

```swift
// App-side code (not part of TextBuffer — documentation for consumers)

class EditorController: NSTextViewDelegate, NSWindowDelegate {
    let textViewBuffer: NSTextViewBuffer
    let transferable: TransferableUndoable<NSTextViewBuffer>
    let puppet: NSUndoManager

    init(textView: NSTextView) {
        self.textViewBuffer = NSTextViewBuffer(textView: textView)
        self.transferable = TransferableUndoable(textViewBuffer)
        self.puppet = transferable.enableSystemUndoIntegration()
        textView.allowsUndo = false
    }

    // NSTextViewDelegate
    func undoManager(for view: NSTextView) -> NSUndoManager? {
        return puppet
    }

    // NSWindowDelegate (optional, for window-level undo)
    func windowWillReturnUndoManager(_ window: NSWindow) -> NSUndoManager? {
        return puppet
    }

    // Switching documents
    func switchTo(buffer: TransferableUndoable<MutableStringBuffer>) {
        // Save current state
        let saved = transferable.snapshot()
        // Load new state
        transferable.represent(buffer)
        // 'saved' can be stored and loaded back later
    }
}
```

---

## 6. Infrastructure & Deployment

Not applicable — TextBuffer is a library package with no deployment infrastructure.

### 6.1 Development Environment

| Aspect | Choice |
|---|---|
| Swift version | 6.2 |
| Platforms | macOS (NSTextView); MutableStringBuffer + TextRope are cross-platform |
| Build | `swift build` |
| Test | `swift test` |
| CI | Existing setup (if any) |

---

## 7. Implementation Plan

### 7.1 Phase Overview

| Phase | Milestone | Name | Goal | Tasks |
|---|---|---|---|---|
| 1 | Op Log | Test Infrastructure | BufferStep, equivalence helpers, failing integration tests | TASK-001, 002 |
| 2 | Op Log | Core Value Types | BufferOperation, UndoGroup, OperationLog — fully tested | TASK-003, 004 |
| 3 | Op Log | TransferableUndoable | New undo decorator, equivalence-tested against Undoable | TASK-005, 006 |
| 4 | Op Log | AppKit Bridge | PuppetUndoManager, Cmd+Z integration | TASK-007 |
| 5 | Op Log | Transfer API | snapshot(), represent(), integration tests | TASK-008, 009 |
| 6 | Rope | Foundation | TextRope target, Node, Summary, COW, construction | TASK-010, 011, 012, 013 |
| 7 | Rope | Core Operations | insert, delete, replace with UTF-16 navigation | TASK-014, 015, 016, 017 |
| 8 | Rope | Verification | Comprehensive unit + stress tests | TASK-018 |
| 9 | Rope | Buffer Integration | RopeBuffer wrapper, drift tests | TASK-019, 020 |
| 10 | Both | Convergence | TransferableUndoable\<RopeBuffer\>, full integration | TASK-021 |

### 7.2 Task Breakdown

### Phase 1: Test Infrastructure

**TASK-001: BufferStep enum and equivalence test scaffolding**
- Depends on:  —
- Size:        S
- Description: Create the `BufferStep` enum (insert, delete, replace,
               select, undo, redo, group) in TextBufferTesting. Create
               `assertUndoEquivalence` that takes an
               `Undoable<MutableStringBuffer>` and
               `TransferableUndoable<MutableStringBuffer>`, iterates
               steps, applies each to both buffers via static dispatch,
               and asserts content + selection equality after each step.
               `TransferableUndoable` doesn't exist yet — guard with
               `#if false` or a stub type.
- Files:       Sources/TextBufferTesting/BufferStep.swift
               Sources/TextBufferTesting/AssertUndoEquivalence.swift
- Acceptance:  File compiles (with guard). Enum covers all cases.
               Assertion function structure is reviewable.

**TASK-002: High-level transfer tests (failing)**
- Depends on:  TASK-001
- Size:        M
- Description: Write three integration tests from plan.md as failing
               tests:
               Test A: transfer-out preserves undo (editor inserts
               twice → snapshot → undo on copy → verify).
               Test B: transfer-in preserves undo (in-memory buffer
               with changes → represent in editor → undo → verify).
               Test C: transitivity (in-memory → represent → snapshot
               → all three undo/redo identically).
               Guarded until API exists.
- Files:       Tests/TextBufferTests/TransferIntegrationTests.swift
- Acceptance:  Test file present, documents three scenarios. Guarded.

### Phase 2: Core Value Types

**TASK-003: BufferOperation and UndoGroup**
- Depends on:  —
- Size:        S
- Description: Implement `BufferOperation` (enum Kind with insert,
               delete, replace) and `UndoGroup` (operations array,
               selectionBefore, selectionAfter, actionName). Both
               Sendable, Equatable, value types.
- Files:       Sources/TextBuffer/OperationLog/BufferOperation.swift
               Sources/TextBuffer/OperationLog/UndoGroup.swift
- Acceptance:  Types compile. Equatable works.

**TASK-004: OperationLog**
- Depends on:  TASK-003
- Size:        L
- Description: Implement `OperationLog` as a value type per the design
               in Section 4.2: history array + cursor for undo/redo,
               grouping stack for nested recording,
               beginUndoGroup/endUndoGroup/record,
               undo(on:)/redo(on:) generic over Buffer.
               Inverse operations use preconditionFailure on errors.
- Files:       Sources/TextBuffer/OperationLog/OperationLog.swift
               Tests/TextBufferTests/OperationLogTests.swift
- Acceptance:  Unit tests covering:
               - Single operation undo/redo round-trip
               - Multi-operation group undo/redo
               - Nested groups merge into parent
               - Redo tail truncation on new edit after undo
               - canUndo/canRedo state transitions
               - Action name propagation (nested promotes to parent)
               - selectionBefore restored on undo
               - selectionAfter restored on redo
               - Undo then redo = identity (no observable difference)
               - Value-type copy independence

### Phase 3: TransferableUndoable

**TASK-005: TransferableUndoable — core Buffer conformance**
- Depends on:  TASK-004
- Size:        L
- Description: Implement `TransferableUndoable<Base>` per Section 4.2.
               Each insert/delete/replace: auto-group if not grouping,
               capture old content, delegate to base, record to log.
               `undoGrouping` with nesting. `undo()`/`redo()` delegate
               to log + restore selection. Does NOT include puppet
               bridge or transfer API yet.
- Files:       Sources/TextBuffer/Buffer/TransferableUndoable.swift
               Tests/TextBufferTests/TransferableUndoableTests.swift
- Acceptance:  Unit tests:
               - insert/delete/replace produce undoable operations
               - undo restores content + selection exactly
               - redo restores content + selection exactly
               - undo then redo = no observable change
               - undoGrouping groups multiple ops as one undo step
               - Nested undoGrouping works
               All tests use MutableStringBuffer as Base.

**TASK-006: Undo equivalence drift tests**
- Depends on:  TASK-001, TASK-005
- Size:        M
- Description: Unguard `assertUndoEquivalence`. Write equivalence
               tests running identical step sequences on
               `Undoable<MutableStringBuffer>` (gold standard) and
               `TransferableUndoable<MutableStringBuffer>` (subject).
               Scenarios: simple insert/undo/redo, delete, replace,
               grouped operations, interleaved edits and undos,
               multiple undos then new edit (redo tail truncation),
               selection state at every step.
- Files:       Tests/TextBufferTests/UndoEquivalenceDriftTests.swift
               Sources/TextBufferTesting/AssertUndoEquivalence.swift
- Acceptance:  All equivalence tests pass.

### Phase 4: AppKit Bridge

**TASK-007: PuppetUndoManager and system integration**
- Depends on:  TASK-005
- Size:        M
- Description: Implement `PuppetUndoManager` as NSUndoManager subclass
               per Section 4.2. Override undo/redo/canUndo/canRedo/
               undoActionName/redoActionName to delegate via
               `PuppetUndoManagerDelegate`. Override `registerUndo`
               variants as no-ops. Add `enableSystemUndoIntegration()`
               to `TransferableUndoable`. Document app-side wiring:
               `textView.allowsUndo = false`,
               `NSTextViewDelegate.undoManager(for:) → puppet`.
- Files:       Sources/TextBuffer/Buffer/PuppetUndoManager.swift
               Sources/TextBuffer/Buffer/TransferableUndoable.swift
               Tests/TextBufferTests/PuppetUndoManagerTests.swift
- Acceptance:  - puppet.canUndo/canRedo reflect log state
               - puppet.undoActionName/redoActionName reflect log
               - puppet.undo() triggers log undo
               - Edit menu shows correct action name
               - Edit > Undo grays out when log is empty
               - NSTextView with allowsUndo=false doesn't register
                 its own actions on the puppet
               - Integration test: NSTextView in window, Cmd+Z works

### Phase 5: Transfer API

**TASK-008: Transfer API — snapshot and represent**
- Depends on:  TASK-005
- Size:        M
- Description: Add `snapshot()` and `represent(_:)` to
               `TransferableUndoable` per Section 4.2.
               `snapshot()` creates `MutableStringBuffer(wrapping:)`,
               copies log. `represent()` preconditions `!log.isGrouping`,
               replaces content via `base.replace`, sets selection,
               copies source log.
- Files:       Sources/TextBuffer/Buffer/TransferableUndoable.swift
               Tests/TextBufferTests/TransferAPITests.swift
- Acceptance:  - snapshot produces independent copy
               - Mutating copy doesn't affect original (and vice versa)
               - represent replaces content, selection, undo history
               - represent + undo restores source's previous state
               - represent + redo after undo restores source's state

**TASK-009: Transfer integration tests**
- Depends on:  TASK-008, TASK-002
- Size:        M
- Description: Unguard and complete the three integration tests:
               Test A: transfer-out preserves undo.
               Test B: transfer-in preserves undo.
               Test C: transitivity.
               Plus: snapshot during active puppet bridge, represent
               clears previous undo state.
- Files:       Tests/TextBufferTests/TransferIntegrationTests.swift
- Acceptance:  All three integration tests pass.

### Phase 6: Rope Foundation

**TASK-010: TextRope target and package structure**
- Depends on:  —
- Size:        S
- Description: Add TextRope target (zero dependencies) and
               TextRopeTests to Package.swift. Add
               `@_exported import TextRope` in TextBuffer.
- Files:       Package.swift
               Sources/TextRope/TextRope.swift (placeholder)
               Sources/TextBuffer/Exports.swift
               Tests/TextRopeTests/TextRopeTests.swift (placeholder)
- Acceptance:  `swift build` succeeds. `swift test` runs.

**TASK-011: Summary and Node types**
- Depends on:  TASK-010
- Size:        M
- Description: Implement `TextRope.Summary` (utf8, utf16, lines with
               add/subtract/of). Implement `TextRope.Node` as internal
               final class: summary, height, chunk (String), children
               (ContiguousArray<Node>), named constants, shallowCopy(),
               emptyLeaf(), ensureUniqueChild(at:), summary(for:).
               TextRope struct with `nonisolated(unsafe) var root: Node`,
               always-rooted (empty leaf).
- Files:       Sources/TextRope/Summary.swift
               Sources/TextRope/Node.swift
               Sources/TextRope/TextRope.swift
               Tests/TextRopeTests/SummaryTests.swift
- Acceptance:  Summary arithmetic correct. Node creation works.
               shallowCopy produces independent node. emptyLeaf
               has zero summary.

**TASK-012: COW infrastructure**
- Depends on:  TASK-011
- Size:        M
- Description: Implement COW path-copying: `ensureUnique()` on TextRope,
               `ensureUniqueChild(at:)` on Node (extract → check →
               write back). Verify copy independence and shared subtree
               preservation.
- Files:       Sources/TextRope/TextRope+COW.swift
               Tests/TextRopeTests/TextRopeCOWTests.swift
- Acceptance:  - Copy shares root (identity)
               - Mutating copy doesn't affect original
               - Path copying creates new nodes only along mutation path

**TASK-013: Leaf construction and content materialization**
- Depends on:  TASK-011
- Size:        M
- Description: Implement `TextRope.init(_ string:)` — split into
               chunks, build balanced tree. Enforce `\r\n` split
               invariant. Implement `content: String` (concatenate
               leaves), `utf16Count`, `utf8Count`, `isEmpty`.
- Files:       Sources/TextRope/TextRope+Construction.swift
               Sources/TextRope/TextRope+Content.swift
               Tests/TextRopeTests/TextRopeConstructionTests.swift
- Acceptance:  Round-trip: `TextRope(s).content == s` for empty,
               single char, multi-chunk, emoji, `\r\n` sequences.
               `utf16Count` matches `s.utf16.count`. `\r\n` never
               split across chunks.

### Phase 7: Rope Core Operations

**TASK-014: UTF-16 offset navigation**
- Depends on:  TASK-013
- Size:        L
- Description: Implement O(log n) findLeaf(utf16Offset:) and
               `content(in utf16Range: NSRange)`. Within leaf: translate
               UTF-16 offset to String.Index via utf16 view walk.
- Files:       Sources/TextRope/TextRope+Navigation.swift
               Tests/TextRopeTests/TextRopeNavigationTests.swift
- Acceptance:  content(in:) correct for single-leaf, multi-leaf,
               boundary, multi-byte/emoji/surrogate-pair, empty range,
               full range.

**TASK-015: Insert operation**
- Depends on:  TASK-012, TASK-014
- Size:        L
- Description: Implement `mutating insert(_:at:)`:
               ensureUnique → navigate → COW path → insert in leaf →
               split if oversized (respecting `\r\n`) → propagate
               splits → update summaries bottom-up.
- Files:       Sources/TextRope/TextRope+Insert.swift
               Sources/TextRope/Node+Split.swift
               Tests/TextRopeTests/TextRopeInsertTests.swift
- Acceptance:  Insert at start/middle/end. Leaf split. Cascading
               splits. Multi-byte boundaries. Summaries correct.
               COW: insert on shared rope doesn't affect copies.

**TASK-016: Delete operation**
- Depends on:  TASK-012, TASK-014
- Size:        L
- Description: Implement `mutating delete(in:)`:
               ensureUnique → navigate start/end → COW path → remove
               content → merge undersized leaves → propagate merges →
               update summaries.
- Files:       Sources/TextRope/TextRope+Delete.swift
               Sources/TextRope/Node+Merge.swift
               Tests/TextRopeTests/TextRopeDeleteTests.swift
- Acceptance:  Delete within leaf, spanning leaves. Leaf merge.
               Cascading merges. Delete all → empty leaf root.
               Summaries correct.

**TASK-017: Replace operation**
- Depends on:  TASK-015, TASK-016
- Size:        M
- Description: Implement `mutating replace(range:with:)`.
               Start with delete + insert composition. Optimize later
               if benchmarks warrant.
- Files:       Sources/TextRope/TextRope+Replace.swift
               Tests/TextRopeTests/TextRopeReplaceTests.swift
- Acceptance:  Replace within leaf, spanning leaves. Shorter/longer
               replacement. Empty string = delete. Empty range = insert.
               Summaries correct.

### Phase 8: Rope Verification

**TASK-018: Rope comprehensive test suite**
- Depends on:  TASK-013 through TASK-017
- Size:        L
- Description: Comprehensive tests: construction (various sizes),
               content round-trip (ASCII, multi-byte, emoji, CJK),
               insert/delete/replace edge cases, COW independence,
               summary correctness, `\r\n` invariant, surrogate pairs,
               rebalancing, stress test (10K random operations vs
               equivalent String operations).
- Files:       Tests/TextRopeTests/TextRopeStressTests.swift
- Acceptance:  All tests pass. Stress test produces no mismatches.

### Phase 9: Buffer Integration

**TASK-019: RopeBuffer — Buffer conformance wrapper**
- Depends on:  TASK-017
- Size:        M
- Description: Implement `RopeBuffer` in TextBuffer target per
               Section 4.3. Wraps TextRope + selectedRange. Conforms
               to Buffer. Selection adjustment logic identical to
               MutableStringBuffer. TextAnalysisCapable via content
               extraction.
- Files:       Sources/TextBuffer/Buffer/RopeBuffer.swift
               Tests/TextBufferTests/RopeBufferTests.swift
- Acceptance:  Compiles. Basic operations work. Selection adjustment
               matches MutableStringBuffer.

**TASK-020: RopeBuffer drift tests**
- Depends on:  TASK-019
- Size:        M
- Description: Port `BufferBehaviorDriftTests` to run RopeBuffer
               against MutableStringBuffer. Same scenarios: insert
               before/at/after cursor, selection interactions,
               sequential operations, mixed insert/delete.
- Files:       Tests/TextBufferTests/RopeBufferDriftTests.swift
- Acceptance:  All drift tests pass. RopeBuffer ≡ MutableStringBuffer.

### Phase 10: Convergence

**TASK-021: TransferableUndoable\<RopeBuffer\> integration**
- Depends on:  TASK-008, TASK-019
- Size:        M
- Description: Verify `TransferableUndoable<RopeBuffer>`:
               - Undo/redo on rope-backed buffer
               - snapshot() from RopeBuffer to MutableStringBuffer
               - represent() from MutableStringBuffer into RopeBuffer
               - Undo equivalence across buffer types
               Proves both milestones compose correctly.
- Files:       Tests/TextBufferTests/RopeTransferIntegrationTests.swift
- Acceptance:  All tests pass. Three buffer types interchangeable
               via snapshot/represent.

### 7.3 Dependency Graph

```
Milestone 1 (Operation Log):

TASK-001 ──► TASK-002
                │
TASK-003 ──► TASK-004 ──► TASK-005 ──┬──► TASK-006
                                     ├──► TASK-007
                                     └──► TASK-008 ──► TASK-009

Milestone 2 (Rope) — parallel from TASK-010:

TASK-010 ──► TASK-011 ──┬──► TASK-012 ──┐
                        └──► TASK-013 ──┼──► TASK-014 ──┬──► TASK-015
                                        │               └──► TASK-016
                                        │                      │
                                        │               TASK-015 + 016
                                        │                   ──► TASK-017
                                        │                         │
                                        └──► TASK-018 ◄──────────┘
                                                │
                                        TASK-017 ──► TASK-019 ──► TASK-020

Convergence:

TASK-008 + TASK-019 ──► TASK-021

Critical path (M1): 003 → 004 → 005 → 008 → 009
Critical path (M2): 010 → 011 → 013 → 014 → 015 → 017 → 019 → 020
Overall:            Both paths → 021
```

### 7.4 Risk-Ordered Priorities

| Risk | Severity | Mitigating Task |
|---|---|---|
| OperationLog undo/redo correctness | High | TASK-004 (unit tests), TASK-006 (equivalence) |
| COW path-copying bugs in rope | High | TASK-012, TASK-018 (stress tests) |
| UTF-16 ↔ UTF-8 offset translation | Medium | TASK-014 (surrogate pair edge cases) |
| Rope rebalancing correctness | High | TASK-015, 016, 018 |
| PuppetUndoManager AppKit interop | Medium | TASK-007 (NSTextView integration test) |

---

## 8. Design Assumptions

| ID | Assumption | Rationale | Risk if Wrong |
|---|---|---|---|
| DA-01 | `allowsUndo = false` fully prevents NSTextView from registering undo actions | Apple documentation states this controls undo registration for text changes | Puppet stack pollution; mitigated by no-op registerUndo override |
| DA-02 | PuppetUndoManager overrides are sufficient for Edit menu | `validateUserInterfaceItem:` reads canUndo/undoMenuItemTitle from undo manager | May need additional overrides if AppKit checks private state |
| DA-03 | Rope leaf chunks of 1-2KB UTF-8 are appropriate | Matches Apple BigString; balances depth vs mutation cost | Tunable via named constants |
| DA-04 | Max 8 children per inner node sufficient for v1 | Depth ~7 for 10K leaves; keeps rebalancing simple | Tunable; 12-16 if benchmarks show depth bottleneck |
| DA-05 | `represent()` should precondition no open undo group | Document switch mid-edit is a programming error | Relax to discard open groups if legitimate use case found |
| DA-06 | Selection-only cursor movement is not undoable | Matches standard text editor UX and NSTextView default | Some editors track selection; this matches the common case |

---

## 9. Design Decisions & Trade-offs

| ID | Decision | Rejected Alternative | Rationale |
|---|---|---|---|
| DD-01 | New TransferableUndoable alongside existing Undoable | Replace Undoable internals | Keeps NSUndoManager implementation as gold standard for drift testing |
| DD-02 | PuppetUndoManager (NSUndoManager subclass) | Proxy action push/sync pattern | Subclass is simpler; Apple explicitly supports custom undo managers |
| DD-03 | UTF-8 rope with cached UTF-16 counts | UTF-16 internal storage | Future-proofs for UTF-8 indexing; matches Apple BigString |
| DD-04 | ContiguousArray for children (v1) | ManagedBuffer inline storage | Simpler; double-COW acceptable for branching factor 8 |
| DD-05 | Always-rooted rope (empty leaf) | Optional root (nil for empty) | Eliminates nil checks in every recursive function |
| DD-06 | String for leaf chunks | [UInt8] raw bytes | Prevents invalid UTF-8 splits; withUTF8 gives raw access |
| DD-07 | Recursive BufferStep.group | Flat begin/end steps | Maps to closure-based undoGrouping API on both types |
| DD-08 | No parent pointers in rope nodes | Weak parent references | Weak refs break isKnownUniquelyReferenced; path-from-root only |

---

## 10. OpenSpec Execution Notes

### 10.1 Execution Order

Tasks MUST be executed in the order listed in Section 7.2. Each task's `Depends on` field defines hard prerequisites. Do not parallelize tasks within a milestone that share dependencies.

Milestone 1 (TASK-001 through TASK-009) and Milestone 2 (TASK-010 through TASK-020) CAN be developed in parallel branches. TASK-021 requires both milestones complete.

### 10.2 Validation Gates

After each task, run `swift test` and verify acceptance criteria before proceeding. The equivalence tests (TASK-006) are a critical gate — if they fail, TransferableUndoable has a behavioral difference from Undoable that must be fixed.

### 10.3 File Structure

```
TextBuffer/
├── Sources/
│   ├── TextRope/
│   │   ├── TextRope.swift
│   │   ├── Summary.swift
│   │   ├── Node.swift
│   │   ├── TextRope+COW.swift
│   │   ├── TextRope+Construction.swift
│   │   ├── TextRope+Content.swift
│   │   ├── TextRope+Navigation.swift
│   │   ├── TextRope+Insert.swift
│   │   ├── TextRope+Delete.swift
│   │   ├── TextRope+Replace.swift
│   │   ├── Node+Split.swift
│   │   └── Node+Merge.swift
│   ├── TextBuffer/
│   │   ├── Buffer/
│   │   │   ├── Buffer.swift                    (existing, unchanged)
│   │   │   ├── AsyncBuffer.swift               (existing, unchanged)
│   │   │   ├── MutableStringBuffer.swift       (existing, unchanged)
│   │   │   ├── NSTextViewBuffer.swift          (existing, unchanged)
│   │   │   ├── Undoable.swift                  (existing, unchanged)
│   │   │   ├── Undoable+NSTextViewBuffer.swift (existing, unchanged)
│   │   │   ├── TransferableUndoable.swift      [NEW]
│   │   │   ├── PuppetUndoManager.swift         [NEW]
│   │   │   └── RopeBuffer.swift                [NEW]
│   │   ├── OperationLog/
│   │   │   ├── BufferOperation.swift           [NEW]
│   │   │   ├── UndoGroup.swift                 [NEW]
│   │   │   └── OperationLog.swift              [NEW]
│   │   ├── Exports.swift                       [NEW]
│   │   └── ... (existing files unchanged)
│   └── TextBufferTesting/
│       ├── assertBufferState.swift             (existing)
│       ├── MakeBufferWithSelectionFromString.swift (existing)
│       ├── BufferStep.swift                    [NEW]
│       └── AssertUndoEquivalence.swift         [NEW]
├── Tests/
│   ├── TextBufferTests/
│   │   ├── ... (existing tests unchanged)
│   │   ├── OperationLogTests.swift             [NEW]
│   │   ├── TransferableUndoableTests.swift     [NEW]
│   │   ├── UndoEquivalenceDriftTests.swift     [NEW]
│   │   ├── PuppetUndoManagerTests.swift        [NEW]
│   │   ├── TransferAPITests.swift              [NEW]
│   │   ├── TransferIntegrationTests.swift      [NEW]
│   │   ├── RopeBufferTests.swift               [NEW]
│   │   ├── RopeBufferDriftTests.swift          [NEW]
│   │   └── RopeTransferIntegrationTests.swift  [NEW]
│   └── TextRopeTests/
│       ├── SummaryTests.swift                  [NEW]
│       ├── TextRopeCOWTests.swift              [NEW]
│       ├── TextRopeConstructionTests.swift     [NEW]
│       ├── TextRopeNavigationTests.swift       [NEW]
│       ├── TextRopeInsertTests.swift           [NEW]
│       ├── TextRopeDeleteTests.swift           [NEW]
│       ├── TextRopeReplaceTests.swift          [NEW]
│       └── TextRopeStressTests.swift           [NEW]
├── Package.swift                               [MODIFIED]
├── plan.md                                     (existing)
├── 2026-03-07_spec-textbuffer-custom-storage.md (existing)
├── research.md                                 (research output)
└── SPEC.md                                     [THIS FILE]
```

### 10.4 Coding Conventions

- **Swift 6.2** strict concurrency mode
- **@MainActor** on all Buffer conformers and undo types (matches existing pattern)
- **Value types** preferred for data (BufferOperation, UndoGroup, OperationLog, Summary, TextRope)
- **Reference types** only where identity/mutability requires (Node, TransferableUndoable, Undoable, buffers)
- **`@inlinable`** on hot-path accessors (matching existing pattern in Buffer.swift)
- **`preconditionFailure`** for programming errors, `throws(BufferAccessFailure)` for user-input errors
- **Test naming**: `test[Unit]_[Scenario]_[ExpectedBehavior]` (matching existing style)
- **TDD**: Write failing tests first, then implement. Equivalence tests are the primary correctness mechanism.

---

## 11. Appendix A: Apple BigString/Rope Reference

Preserved from research for future reference when implementing the rope.

### Architecture (swift-collections, `_RopeModule`)

- **Module status:** `_RopeModule` — underscore prefix = internal/unstable API. Not for external consumption.
- **Availability:** `@available(SwiftStdlib 6.2, *)`, `#if compiler(>=6.2) && !$Embedded`
- **Known issues:** FIXME in Package.swift: `_modify` accessors broken in Swift 6 mode; module runs in Swift 5 language mode.
- **Generic rope:** `Rope<Element: RopeElement>` with `RopeSummary` and `RopeMetric` protocols.
- **BigString:** `Rope<_Chunk>` where chunks are `ManagedBuffer<(), UInt8>` storing UTF-8 bytes.

### Key Design Patterns

- **Internal encoding:** UTF-8 (`ManagedBuffer<(), UInt8>`)
- **Summary:** Caches `utf8`, `utf16`, `unicodeScalars`, `characters` counts per node
- **Metrics:** Protocol-based navigation — `_UTF8Metric`, `_UTF16Metric`, `_CharacterMetric`, `_UnicodeScalarMetric`
- **Branching factor:** Max 15, min 8 (in release builds; 10 in debug)
- **COW:** Reference-counted nodes via `ManagedBuffer`, `isKnownUniquelyReferenced`

### Why We Don't Use It Directly

1. Unstable API (`_RopeModule` prefix)
2. `SwiftStdlib 6.2` availability constraint
3. API mismatch: `BidirectionalCollection<Character>` with opaque `BigString.Index`, not integer-offset `Buffer` operations
4. Over-complex for our needs: grapheme cluster break tracking, ingester pipelines, ~5000 lines vs our ~500-800

### What We Borrow

- UTF-8 storage with multi-count summary (utf8 + utf16 + lines)
- Metric-based tree navigation by UTF-16 at the `Buffer<NSRange>` boundary
- `ContiguousArray`/`ManagedBuffer` for node children
- Path-copying COW discipline

---

## 12. Appendix B: COW Rope Sub-Agent Review Findings

Preserved from sub-agent review for implementation guidance.

### Critical Implementation Notes

1. **Sendable placement:** `Node` has no Sendable conformance. `TextRope: Sendable` with `nonisolated(unsafe) var root: Node`. This matches `Array`'s pattern — the storage class is not Sendable; the value-semantic wrapper takes responsibility.

2. **`isKnownUniquelyReferenced` with optionals:** Works correctly via the `T?` overload. Not applicable since we use always-rooted design.

3. **`isKnownUniquelyReferenced` with array elements:** Unreliable via direct subscript access. Must extract → check local variable → write back. The local variable holds a second reference, so the check returns false if *any other* reference exists — which is correct.

4. **Double-COW with `ContiguousArray<Node>`:** Real but manageable. Path-copying at depth D with branching factor B costs O(B × D) pointer copies (entire children array at each level). With B=8, D≤7: max 56 pointer copies per mutation.

5. **`ManagedBuffer` upgrade path:** Single allocation per inner node (children inline). Superior for path-copying where new nodes are constructed with known child counts. Documented as future optimization.

6. **No parent pointers:** Weak references break `isKnownUniquelyReferenced` (always returns false). Use path-from-root traversal.

7. **`\r\n` cross-chunk invariant:** Never split between `\r` and `\n`. Enforce during chunk splitting: if byte before split is `\r` and byte after is `\n`, adjust split point.

8. **Cursor type for sequential access:** Not in v1, but important for future. Sequential access via O(log n) per step is wasteful for line-by-line reading. A cursor maintaining a stack of `(node, childIndex, offset)` enables O(1) amortized sequential navigation. Design rope internals to accommodate this later.

9. **Index invalidation:** Use version counter on TextRope incremented on every mutation. Future opaque index types carry creation version; stale access is a precondition failure. Not needed for v1 since all operations use integer offsets.

---

## Document History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-03-11 | Solution Architect | Initial spec |
