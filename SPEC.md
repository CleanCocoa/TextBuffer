# Solution Specification: TextBuffer — Operation Log & Rope

**Version:** 1.3
**Date:** 2026-03-11
**Author:** Solution Architect (AI-Assisted)
**Status:** Draft
**Source Requirements:** 2026-03-07_spec-textbuffer-custom-storage.md

---

## 1. Executive Summary

TextBuffer is a Swift library providing a `Buffer` protocol for text editing with two existing conformers (`MutableStringBuffer`, `NSTextViewBuffer`) and an `Undoable<Base>` decorator backed by `NSUndoManager`. This spec adds two milestones:

**Milestone 1 (Operation Log):** A value-type `OperationLog` that records reversible deltas, powering a new `TransferableUndoable<Base>` decorator. Because the log is a plain value type, buffer transfer (copying content + selection + undo history between editor and in-memory buffers) becomes a simple value copy. A `PuppetUndoManager` subclass bridges to AppKit's Cmd+Z and Edit menu. The existing `Undoable<Base>` remains as the behavioral gold standard for equivalence testing.

**Milestone 2 (Rope):** A `TextRope` data structure in a standalone package target — a balanced B-tree of UTF-8 string chunks with O(log n) insert/delete/replace. UTF-16 counts cached in node summaries enable O(log n) `NSRange` translation. COW via `isKnownUniquelyReferenced` on reference-type nodes. A `RopeBuffer` wrapper adds `Buffer` conformance.

The milestones are structurally independent and can be developed in parallel branches. They converge when `TransferableUndoable<RopeBuffer>` is verified.

### Reading Guide

| You want to...                                | Read                                              |
|-----------------------------------------------|---------------------------------------------------|
| Understand the system shape and component map | §2 Architecture Overview                          |
| Look up a type's contract or behavioral spec  | §4 Data Architecture                              |
| See the public API surface at a glance        | §5 API Specification                              |
| Start implementing a task                     | [TASKS.md](TASKS.md) → task's Spec reference → §4 |
| Understand why a decision was made            | [docs/adr/](docs/adr/)                            |
| Wire up AppKit Cmd+Z integration              | §5.3 AppKit Integration Pattern                   |

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

    // Prevent external undo registration.
    // This override is illustrative; the implementation must neutralize
    // all relevant NSUndoManager registration entry points that could let
    // external callers pollute the puppet's state.
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

See ADR-004 for encoding rationale.

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

See **[TASKS.md](TASKS.md)** for the full task breakdown (21 tasks), dependency graph, and risk-ordered priorities.

---

## 8. Design Assumptions & Decisions

Design decisions and their rationale are recorded in `docs/adr/`. Key ADRs:

| ADR | Topic |
|---|---|
| [ADR-001](docs/adr/adr-001--dual-undo-implementations.md) | Why TransferableUndoable exists alongside Undoable |
| [ADR-002](docs/adr/adr-002--operation-log-as-value-type.md) | OperationLog as value type — the core transfer enabler |
| [ADR-003](docs/adr/adr-003--puppet-undo-manager-via-subclass.md) | PuppetUndoManager via subclass + allowsUndo=false |
| [ADR-004](docs/adr/adr-004--utf8-rope-with-cached-utf16-counts.md) | UTF-8 rope storage with cached UTF-16 counts |
| [ADR-005](docs/adr/adr-005--contiguous-array-children-with-managed-buffer-upgrade-path.md) | ContiguousArray children with ManagedBuffer upgrade path |
| [ADR-006](docs/adr/adr-006--always-rooted-rope.md) | Always-rooted rope (empty leaf, no optional root) |
| [ADR-007](docs/adr/adr-007--no-parent-pointers-in-rope-nodes.md) | No parent pointers in rope nodes |
| [ADR-008](docs/adr/adr-008--selection-as-group-metadata.md) | Selection is group metadata, not an undo step |
| [ADR-009](docs/adr/adr-009--undo-redo-as-proper-inverses.md) | Undo and redo as proper inverses |

**Remaining assumption not covered by ADRs:**

- **DA-05:** `represent()` preconditions that no undo group is currently open. A document switch mid-edit-group is a programming error. If a legitimate use case arises, relax to discard open groups.

**Implementation convention (not a design decision):**

- `BufferStep.group` uses a recursive case (not flat begin/end steps) because it maps directly to the closure-based `undoGrouping { }` API on both `Undoable` and `TransferableUndoable`.
- Rope leaf chunks use `String` (not `[UInt8]` raw bytes) because `String.Index` prevents invalid UTF-8 splits at chunk boundaries, and `withUTF8` provides raw byte access when needed.

---

## 10. OpenSpec Execution Notes

### 10.1 Execution Order

Tasks MUST be executed in the order listed in [TASKS.md](TASKS.md). Each task's `Depends on` field defines hard prerequisites. Do not parallelize tasks within a milestone that share dependencies.

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

## 11. Research References

Detailed research is preserved in companion files:

- **Apple BigString/Rope analysis:** `research.md` and ADR-004. The swift-collections `_RopeModule` was evaluated and rejected as a direct dependency (unstable API, availability constraints, API mismatch) but its architecture informed our design decisions. Key borrowed patterns: UTF-8 storage with multi-count summaries, metric-based tree navigation, path-copying COW discipline.
- **COW sub-agent review:** Detailed findings on `isKnownUniquelyReferenced` behavior, double-COW costs, and Sendable patterns are captured in ADR-005, ADR-006, and ADR-007. Implementation-specific notes (extract→check→write-back pattern for array elements, `\r\n` split invariant) are embedded in the Node type definition (Section 4.3) and task descriptions (TASK-013, TASK-015).

**Future consideration not yet an ADR:** A version counter on `TextRope` (incremented on every mutation) would enable opaque index types with staleness detection. Not needed for v1 since all operations use integer offsets. Revisit when adding a cursor type for sequential access.

---

## Document History

| Version | Date | Author | Changes |
|---|---|---|---|
| 1.0 | 2026-03-11 | Solution Architect | Initial spec |
| 1.1 | 2026-03-11 | Solution Architect | Extracted ADR-001 through ADR-009; trimmed Sections 8–9 and appendices to cross-references |
| 1.2 | 2026-03-11 | Solution Architect | Extracted §7.2–7.4 task breakdown to TASKS.md; added reading guide |
| 1.3 | 2026-03-11 | Solution Architect | Clarified PuppetUndoManager example scope; fixed task execution reference to TASKS.md |
