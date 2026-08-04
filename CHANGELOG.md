# Changelog

## 0.10.1

### Fixed

- `TextRope`: inserting or deleting near an internal chunk boundary could leave a grapheme cluster — for example a combining mark and its base character, a zero-width-joiner sequence, or a variation selector with its base — spanning two internal chunks, violating the rope's structural invariant that no cluster crosses a chunk seam. Seam repair previously recognized only the CRLF pair; it now covers all grapheme clusters, with CRLF as one case of the general rule. No API or content behavior change — document text, counts, and all read results are identical; only internal leaf-boundary placement differs.

### Changed

- `TextRope.delete(in:)` with an empty out-of-bounds range, `TextRope.insert("", at:)` with an out-of-bounds offset, and the TextBuffer `NSRange` delete wrapper with a zero-length out-of-bounds location now trap instead of silently succeeding — the bounds preconditions run before the empty-operand early returns, matching the 0.10.0 tightening of the read APIs. In-bounds empty operands remain no-ops. `RopeBuffer` and `SendableRopeBuffer` are unaffected — they validate ranges before delegating.

## 0.10.0

### Changed

- **Breaking (TextRope product only):** `TextRope`'s public range-taking API is now `Range<Int>` over UTF-16 code unit offsets — `content(in:)`, `delete(in:)`, and `replace(range:with:)` take half-open integer ranges, and the target no longer imports Foundation. The NSRange forms moved, signature-identical, to `@inlinable` extensions in the TextBuffer target, and the composed-character-sequence APIs are now provided by TextBuffer as well (their contract is defined by `NSString` semantics and is unchanged). Consumers importing `TextBuffer` — which re-exports `TextRope` — see the same combined API surface as before and need no changes; only a consumer of the standalone `TextRope` product using NSRange directly must switch to `Range<Int>` or import TextBuffer. One edge tightened with the move: the NSRange `delete(in:)` wrapper now traps on a `NSNotFound`/negative location even with length 0, where the old method silently no-opped.

- `TextRope` equality, multi-level concurrent copy-on-write, and transfer round-trips are now covered directly: rope-to-rope `==` has its first tests (including equal content across different tree shapes), the parallel-mutation tests exercise a height-3 tree so path-copying below the root is verified (with a documented developer-local ThreadSanitizer gate), and the convergence idempotence test chains each round-trip's receiver into the next pass as the spec always required.
- `TextRope.content(in:)`, `composedCharacterSequences(in:)`, and `composedCharacterSequence(at:)` now trap on out-of-bounds ranges even when the range is empty. Previously a zero-length range past the end (or with a negative or `NSNotFound` location) silently returned `""`, bypassing the documented precondition; the bounds check now runs before the empty-range early return. `RopeBuffer` and `SendableRopeBuffer` are unaffected — they validate ranges before delegating.

### Fixed

- `TextRope`: comparing unequal ropes no longer materializes both documents. `==` now rejects in O(1) when the cached root summaries (UTF-8 bytes, UTF-16 units, line count) differ — the common case for the per-keystroke echo-suppression comparison in consuming apps; equal-summary comparisons still fall through to exact content comparison, so equality semantics are unchanged. Large inserts into an existing document are confirmed linear (single-pass re-chunk; a 4× larger insert costs 4.0×, not 16×).
- `TextRope`: deleting from a rope with a single owner now mutates the tree in place again. The delete descent held a second strong reference to the child it was about to modify, so the copy-on-write uniqueness check always failed and every delete copied its whole path even when nothing shared the tree. Reads, inserts, and replaces were unaffected; content was always correct — this was purely a per-delete allocation cost. On-path node identity is now pinned by tests for delete, insert, and replace.
- `RopeBuffer` and `SendableRopeBuffer`: reads inside long regional-indicator (flag) runs return the correct flag again. The windowed composed-sequence expansion could start its window mid-run and flip UAX #29 pairing parity, so `unsafeCharacter(at:)`/`content(in:)` on documents longer than 129 UTF-16 units returned adjacent-but-wrong pairs (🇪🇩 for 🇩🇪) at offsets past the window radius — the only defect in the 0.9.0 fold that returned wrong text. The window start now anchors to the start of the contiguous flag run (capped at 4,096 UTF-16 units, beyond which the read falls back to whole-document expansion), restoring exact parity with `MutableStringBuffer` at every offset.

- `TextRope`: chunk size bounds hold again after CRLF-adjacent edits. The balanced split point's fallback ignored its legal window, so specific edits — inserting between a `\r` and `\n` at full leaves, deletes rejoining a split `\r\n`, deletes redistributing near an emoji at the window edge — produced oversized leaves or a stable undersized leaf that survived hundreds of subsequent operations. Splits now search bidirectionally for the nearest `Character` boundary and redistribute merge combinations into up to three balanced chunks; when no conforming boundary exists, the split deviates minimally, and a single grapheme cluster wider than a chunk occupies one whole leaf (ADR-012). Splits also no longer starve a chunk in isolation when redistributing with an adjacent leaf would conform. No API or content behavior change — document text, offsets, and reads are identical; only internal leaf shapes differ.

## 0.9.1

### Fixed

- `NSTextViewOperationLogBridge` now records compositions driven through the view's real delegate callbacks — a real IME commit (e.g. macOS Pinyin's Return, which commits the raw latin letters) was never entered into the log, so undoing everything unwound every other group and left the committed letters behind. `NSTextView` flips `hasMarkedText()` before consulting the delegate and fires no `textDidChange` for marked-only changes, so the baseline the bridge expected to stage from a pre-composition `shouldChangeText` forward never existed; the commit's own forward was gated as an intermediate and its `textDidChange` found nothing to record. The composition baseline is now captured at the first gated `shouldChangeText` forward, whose content and selection are still pre-composition. The hand-simulated sequence the tests previously drove (staging before `setMarkedText`, `textDidChange` per intermediate) still records identically.

## 0.9.0

### Added

- `RopeBuffer` now prints its selection state via `CustomStringConvertible` — a selected range is wrapped in guillemets (`«...»`), an insertion point shows as `ˇ` — matching `MutableStringBuffer`, `SendableRopeBuffer`, and the `TextBufferTesting` notation, so drift-test failure output is readable for rope-backed buffers.
- `TextRope.composedCharacterSequences(in:)` and `TextRope.composedCharacterSequence(at:)` — rope equivalents of `NSString.rangeOfComposedCharacterSequences(for:)` and `rangeOfComposedCharacterSequence(at:)` that expand a UTF-16 range or offset to composed character sequence boundaries, materializing only a small window around the target (doubled whenever the expansion touches a window edge) rather than the whole document. The rope buffers' composed-sequence read fix below routes through them, but they are public API in their own right.

### Fixed

- `TextRope`: inserting an LF-leading string at a chunk boundary after a CR-terminated chunk no longer splits a `\r\n` pair across adjacent leaves. The insert unwind now repairs the seam by redistributing the two boundary chunks through the grapheme-safe balanced split point, for sibling leaves and across subtree boundaries alike — the guarantee the delete path already enforced.
- `RopeBuffer` and `SendableRopeBuffer`: `content(in:)` and `unsafeCharacter(at:)` now expand their ranges to composed character sequence boundaries, matching `MutableStringBuffer`'s `NSString`-backed semantics on partial surrogate pairs and combining marks. The expansion materializes only a small window around the range via the new `TextRope.composedCharacterSequences(in:)`/`composedCharacterSequence(at:)`, not the whole document.
- `TextRope`: construction no longer emits an undersized tail chunk or an undersized tail group. Chunking balances the last two chunks when the remainder would fall below `minChunkUTF8` and cuts before a straddling `\r` instead of overflowing `maxChunkUTF8` past the `\n`; tree grouping balances the last two groups the same way when the tail would fall below `minChildren`. The same input string now yields a different — conforming — leaf layout than in 0.8.2.
- `TextRope`: a large insert into a single-leaf rope used to split once and promote the arbitrarily oversized remainder as the root's sibling. The root-leaf path now splices into the chunk and, on overflow, rebuilds through the construction chunk distribution, so every produced leaf lands within `minChunkUTF8...maxChunkUTF8` at any insert size.
- `TextRope`: a single 50/50 split of an overflowing inner node could leave both halves still over `maxChildren` (56 children became 2×28). `splitInner` now distributes evenly into sibling groups of `minChildren...maxChildren`; the insert unwind splices all siblings into the parent, and the root path rebuilds through `buildTree` when the promoted sibling set itself overflows.
- `TextRope`: the leaf split point was a greedy cut at `maxChunkUTF8` on raw byte offsets, which could split extended grapheme clusters and overflowed the maximum by one byte to hop a straddling `\r\n`. It now targets the UTF-8 midpoint and snaps backward to the nearest grapheme-cluster boundary, so both halves stay at or above `minChunkUTF8` whenever the chunk is at least twice the minimum, neither half exceeds the maximum, and no `\r\n` pair or grapheme cluster is split. Construction's chunk end delegates to the same boundary-snapping split point.
- `TextRope`: delete's leaf merge stranded undersized leaves in three cases; all three are handled now. Combined content over `maxChunkUTF8` is redistributed at a balanced split point so both leaves land in range, a trailing undersized leaf absorbs or redistributes leftward through its already-merged neighbor, and the balanced split point searches its window bidirectionally so grapheme-boundary adjustment cannot undershoot the minimum — keeping `\r\n` pairs and multi-byte characters intact.
- `TextRope`: merging two inner nodes whose combined child count exceeds `maxChildren` now redistributes the children so both halves land in `minChildren...maxChildren`, a trailing undersized inner node absorbs or redistributes leftward, and the merge pass re-runs on the junction so an unfixable undersized child carried out of a single-child parent is absorbed by its new siblings — cascading level by level on the unwind. Delete from an inner node now consumes the child-undersize signal instead of discarding it.
- `TextRope`: a delete that removed the text between a `\r` ending one leaf and a `\n` starting the next never triggered the merge pass when neither leaf went undersized, leaving the pair split across leaves in violation of the chunk invariant — including across subtree boundaries. The merge pass now also fires on a detected seam, and the leaf and inner merge loops absorb the seam pair, re-splitting at a grapheme-safe balanced point — the delete-side counterpart of the insert-unwind seam repair listed first in this section.

### Changed

- M2 rope verification complete: structural invariants — chunk size bounds, children count bounds, `\r\n` never split across leaves — are enforced by the tree validator after any sequence of insert, delete, or replace, and verified under 4-seed 10k-operation randomized stress.

## 0.8.2

### Fixed

- `NSTextViewOperationLogBridge.undo()`/`redo()` now resolve a stale composition baseline — one left by an unmark without a character-changing `textDidChange()` — before replaying, exactly as the next staging call and `sendableSnapshot()` already did. Previously nothing resolved it across a replay (the replay's own change callbacks are suppressed), so after the replay changed the view's length, the next staging call ran the composition commit against post-replay content: the committed length became the replay's delta and the replacement was grabbed from text that was never composed, appending a fabricated undo group that passed the consistency check by construction, truncated the redo tail, and on a later undo deleted pre-existing text. A resolution that commits truncates the redo tail, so a `redo()` right after it reapplies nothing — the unmarked composition was the newer edit.

## 0.8.1

### Fixed

- `NSTextViewOperationLogBridge.sendableSnapshot()` now requires quiescence and traps otherwise, instead of capturing torn state. During `undo()`/`redo()` replay the view already holds post-replay content while the log cursor is still pre-replay, and while the view `hasMarkedText()` the uncommitted composition is in the view but gated out of the log — a snapshot taken in either state restored to a buffer that repeated an operation or trapped on out-of-range undo. Snapshot after `undo()`/`redo()` returns and after the composition commits or cancels; an active composition is not resolved because the user may still cancel it. A stale baseline left by an unmark without a character change is resolved first, exactly as the next staging call would resolve it, so that snapshot is consistent instead of silently missing the composition.
- A vetoed multi-range edit no longer erases history at the next unrelated commit. `shouldChangeText(inRanges:replacementStrings:)` armed the discard for its own `textDidChange()`; when the host vetoed the edit, no `textDidChange()` arrived to consume it, and the flag fired on the next successful edit. Every staging call, singular or plural, now re-decides the discard for its own edit — a `nil`-replacement (attribute-only) forward clears it too, while a committed multi-range edit still discards.

## 0.8.0

### Added

- `NSTextViewOperationLogBridge.shouldChangeText(inRanges:replacementStrings:)` — plural funnel for `NSTextViewDelegate.textView(_:shouldChangeTextInRanges:replacementStrings:)`. A single-range forward delegates to the singular funnel; an edit spanning more than one range (multiple insertion points, find-and-replace-all) marks the log for discard at the next `textDidChange()` — drop history rather than record a delta that would not replay. Hosts forwarding only the singular method get the divergence discard only while an edit is staged; forward the plural method too so multi-range edits can never leave the log silently stale.
- Undo groups that open a coalescing run (single-character inserts, deletes) are named "Typing" (unlocalized), so a system undo manager's `undoMenuItemTitle` yields "Undo Typing", matching native `NSTextView` undo. Multi-character inserts (paste) and replaces stay unnamed: the log cannot tell a paste from a drop, and a wrong name is worse than a bare "Undo".

### Fixed

- `PuppetUndoManager` swallows block-based `registerUndoWithTarget:handler:` like it already swallowed the selector-based form. Native registrations from a text view with `allowsUndo` enabled no longer accumulate (and retain their handlers) forever in the puppet's never-closed init group.
- `PuppetUndoManager.prepare(withInvocationTarget:)` returns a swallowing invocation target instead of `self`, so invoking a non-`UndoManager` selector on the result no-ops instead of crashing with `doesNotRecognizeSelector:`. Nothing is recorded either way.

## 0.7.0

### Added

- `NSTextViewOperationLogBridge` — mirrors `NSTextView` edits into an `OperationLog` while the text view stays the live content authority. Feed it by forwarding `shouldChangeText(in:replacementString:)` and `textDidChange()` from the view's delegate; `undo()`/`redo()` replay log groups back onto the view (content and selection) through the `shouldChangeText`/`didChangeText`-wrapped storage mutation so the view re-emits its regular change callbacks and failures surface as typed `BufferAccessFailure`; `enableSystemUndoIntegration()` returns a `PuppetUndoManager` for AppKit's Edit menu and Cmd+Z. Replay-driven view mutations are guarded against re-recording.
- macOS-style undo coalescing in `NSTextViewOperationLogBridge`: a continuous typing run records as one undo group, never one per keystroke; `breakUndoCoalescing()` is the public seam for forwarding interaction breaks (mouse-down, cursor repositioning, focus changes). Coalescing lives log-side as an extension of `OperationLog`'s per-edit auto-grouping, so it travels with snapshots; a run also ends on undo/redo, a kind or position mismatch, or an explicit group.
- Delete-run coalescing, matching native deletion undo: a backspace run extends while each delete ends where the previous one started; a forward-delete run extends at a constant location. Runs are same-kind only — a delete never joins an insert run and vice versa — and replace never coalesces.
- Multi-character inserts (paste) record their own undo group and close the typing run instead of joining it; a committed IME composition likewise never joins a preceding run nor opens one. An attribute-only change (`nil` replacement string) breaks the typing run, matching native formatting-during-typing behavior.
- `NSTextViewOperationLogBridge.sendableSnapshot()` — captures the view's content, selection, and the mirrored log as a `SendableRopeBuffer` for storage or transfer, mirroring `TransferableUndoable.sendableSnapshot()`. Restore by configuring a fresh view from the snapshot and handing its log to `init(textView:log:)`; the initializer closes any open typing run in the adopted log, so a re-presented buffer never resumes an old run.
- IME/marked-text gating in `NSTextViewOperationLogBridge`: composition intermediates record nothing while the view `hasMarkedText()`; the committed composition records exactly once, as one edit against the pre-composition baseline; a cancelled composition records nothing. A baseline left over by an unmark without a character-changing `textDidChange` is resolved (committed or discarded) before the next ordinary edit stages, so it cannot fold into stale composition math.
- Attribute-only edits (`nil` replacement string, no character changes) record nothing and leave the log replayable; a programmatic full replace records as exactly one undo group.

### Changed

- `OperationLog` equality compares recorded history only (history, cursor, grouping stack) and ignores whether a typing run is open, so a coalescing break never reads as a history change in snapshot comparisons.

## 0.6.0

### Added

- DocC documentation for all three library products: TextBuffer, TextRope, and TextBufferTesting each have a DocC catalog with a landing page and organized topic groups.
- "Choosing a Buffer" article — decision guide with comparison table and code examples, positioning `SendableRopeBuffer` as the recommended in-memory buffer.
- "Undo and Redo" article — explains both `UndoManager`-based and `OperationLog`-based strategies with code examples.
- Doc comments for previously undocumented public types: `TextBuffer` protocol, `RopeBuffer`, `SendableRopeBuffer`, `TransferableUndoable`, `PuppetUndoManager`, `OperationLog`, `UndoGroup`, `BufferOperation`, `BufferContent`, `TextRope`, and all TextBufferTesting helpers.

### Changed

- **BREAKING:** `InMemoryBuffer` typealias now points to `SendableRopeBuffer` (was `MutableStringBuffer`). The rope-backed, `Sendable` value type with built-in undo is the proper in-memory buffer for production use. `MutableStringBuffer` remains available by its concrete name.
- `EditingBuffer` typealias added for `TransferableUndoable<RopeBuffer>` — the `@MainActor` buffer for UI-connected editing with system undo integration.
- ADR-011: Multi-buffer in-memory architecture.

## 0.5.0

### Added

- `TextBuffer` protocol — base protocol without `AnyObject`, enabling struct conformers. `Buffer` refines it, so existing class conformers are unaffected.
- `SendableRopeBuffer` — `Sendable` value-type buffer combining `TextRope` + `OperationLog` + selection. Conforms to `TextBuffer`, `TextAnalysisCapable`, and `CustomStringConvertible`. Designed for concurrent batch processing via `TaskGroup`.
- `SendableRopeBuffer.comparator(_:_:...)` — factory returning `@Sendable` comparison closures. Callers choose components to compare (`.content`, `.selection`, `.undoHistory`).
- `OperationLog.popUndo()` / `popRedo()` — cursor manipulation methods for struct-based undo replay without exclusivity violations.
- `SendableRopeBuffer` conversion surface: `init(copying:)`, `init(from:)`, `toRopeBuffer()`, `toTransferableUndoable()`.
- `TransferableUndoable.sendableSnapshot()` / `represent(_: SendableRopeBuffer)` for round-trip snapshot transfer with undo history.
- `makeSendableRopeBuffer(_:)` factory in `TextBufferTesting`.
- `applyStep(_:to: inout SendableRopeBuffer)` and `assertSendableUndoEquivalence(initial:steps:)` for step-driven undo equivalence testing.
- ADR-010: Sendable value-type buffer via protocol split.

### Changed

- `TextAnalysisCapable` now refines `TextBuffer` instead of `Buffer`, enabling struct conformers to provide `wordRange`/`lineRange`.
- `assertBufferState`, `MutableStringBuffer.init(copying:)`, `RopeBuffer.init(copying:)` accept `TextBuffer` (widened from `Buffer`).
- `change(buffer:to:)` gains an `inout` overload for `TextBuffer` value types.

### Deprecated

- `change(buffer:to:)` non-`inout` overload — use `change(buffer: &buffer, to:)` instead.

### Fixed

- `Undoable`: replaced `isolated deinit` with nonisolated deinit using `MainActor.assumeIsolated`. The Swift 6.2 runtime aborts (signal 6) when a `@MainActor` class with `isolated deinit` is deallocated without a running RunLoop (XCTest CLI, background threads).
- TextRope: CRLF split invariant in delete's leaf merge.
- TextRope: precondition guards on public API for bounds checking.
- TextRope: tree invariant validation for oversized leaf siblings.

## 0.4.0

### Added

- `TextRope` — B-tree rope data structure with O(log n) insert, delete, and replace. UTF-8 storage with cached UTF-16 counts. Value semantics with copy-on-write.
- `RopeBuffer` — `Buffer` and `TextAnalysisCapable` conformance wrapping `TextRope`, with selection tracking. Drop-in alternative to `MutableStringBuffer` for large documents.
- New `TextRope` library target (zero dependencies), re-exported by `TextBuffer`.

## 0.3.0

### Added

- `TransferableUndoable` buffer wrapper with `OperationLog`-backed undo/redo.
- `snapshot()` and `represent(_:)` for transferring buffer state (content + undo history) between buffers.
- `PuppetUndoManager` for bridging `TransferableUndoable` into AppKit's `UndoManager` system.
- `BufferOperation`, `UndoGroup`, and `OperationLog` value types for inspectable undo history.
- `undoGrouping(actionName:_:)` for grouping multiple mutations into a single undo step.

### Changed

- Renamed `MutableStringBuffer.init(wrapping:)` to `init(copying:)`.
- `UndoGroup` properties are now `internal(set)`.
- Replaced `assert` with `precondition` for overflow check in `resized(by:)`.
- Replaced `try!` and force unwraps with `preconditionFailure` diagnostics.
- Requires macOS 13+ (added platform requirement to Package.swift).

## 0.2.0

Initial public release.
