# Post-0.4.0 Review Findings

Three review agents assessed the TextRope and RopeBuffer implementation. Findings below, grouped by priority.

## Critical

### 1. CRLF split invariant missing in delete's leaf merge

`TextRope+Delete.swift` has its own `leafSplitPoint` that does NOT check for `\r\n` boundaries. The construction and insert paths both respect this invariant. After a delete triggers a leaf merge that exceeds `maxChunkUTF8`, the re-split can place `\r` and `\n` in separate chunks.

**Fix:** Add the same `\r\n` boundary check from `TextRope+Construction.swift`'s `splitPoint` to `leafSplitPoint` in the delete file.

### 2. No bounds validation on public TextRope API

`insert(_:at:)`, `delete(in:)`, and `content(in:)` accept negative or out-of-range offsets silently. Negative offsets cause undefined behavior; offsets beyond `utf16Count` silently append or truncate.

**Fix:** Add `precondition` guards at the top of each public method:
```swift
precondition(utf16Offset >= 0 && utf16Offset <= utf16Count)
precondition(utf16Range.location >= 0 && utf16Range.location + utf16Range.length <= utf16Count)
```

### 3. RopeBuffer missing `init(copying:)`

`MutableStringBuffer` has `init<Wrapped: Buffer>(copying:)`. RopeBuffer does not. Generic code that copies any Buffer will fail to compile with RopeBuffer.

**Fix:**
```swift
public convenience init<Wrapped: Buffer>(
    copying buffer: Wrapped
) where Wrapped: Buffer, Wrapped.Range == NSRange, Wrapped.Content == String {
    self.init(buffer.content)
    self.selectedRange = buffer.selectedRange
}
```

### 4. No tree invariant validation in tests

Tests only check `rope.content` — never verify tree structure. Rebalancing bugs could silently violate height balance, child count (4–8), or leaf size (1024–2048 bytes) while content stays correct.

**Fix:** Write an internal `verifyTreeInvariants(_:)` helper that recursively checks:
- All leaves at same depth
- Inner nodes have `minChildren...maxChildren` children (except root)
- Leaf chunks between `minChunkUTF8` and `maxChunkUTF8` (except single-leaf trees)
- Summary matches actual content at every node

Use it in all rebalancing-related tests.

## Important

### 5. RopeBuffer missing `CustomStringConvertible`

MutableStringBuffer has the `«selection»` / `ˇinsertion` debug format. RopeBuffer prints as a generic class reference. This breaks `assertBufferState` readability for RopeBuffer.

**Fix:** Add the same conformance from MutableStringBuffer (uses `NSMutableString` on `self.content`).

### 6. `wordRange(for:)` is O(n) on RopeBuffer

The default `TextAnalysisCapable` implementation calls `self.content` (O(n) full reconstruction) on every `wordRange` call. MutableStringBuffer doesn't have this problem because its `content` is a stored property.

**Fix (short-term):** Override `wordRange(for:)` in RopeBuffer to extract only the relevant portion via `content(in:)`. Investigate: the free function `computeWordRange` in `Buffer+wordRange.swift` takes an `NSString` — can we pass a smaller substring?

### 7. `content` property is O(n) with no API signal

`TextRope.content` concatenates all leaves on every access. Consumers may call it in tight loops expecting O(1). `RopeBuffer.content` delegates to it.

**Investigate:** Consider whether to rename to a method (`makeContent()`) to signal cost, or cache with invalidation. The `Equatable` conformance on TextRope also calls `content` — could be expensive on large ropes.

### 8. Delete merge cascades untested

`mergeUndersizedLeaves` and `mergeUndersizedInnerNodes` in `TextRope+Delete.swift` have multiple branches (merge succeeds, merge fails because combined too large, split after merge, parent undersize propagation). None are tested in isolation.

**Fix:** Add targeted tests that construct ropes with specific leaf/node sizes to exercise each branch. Use tree invariant validator (#4) to verify results.

### 9. RopeBuffer drift tests incomplete

RopeBufferDriftTests has 10 tests. BufferBehaviorDriftTests has ~20 scenarios. Missing from RopeBuffer drift tests:
- Insert at selection start / within selection / at selection end
- Delete overlapping selection start / overlapping selection end
- Replace with shorter / longer / multi-byte content
- Mixed insert + delete accumulation

**Fix:** Port remaining scenarios from BufferBehaviorDriftTests.

### 10. Multi-byte characters at chunk boundaries not targeted

Tests use emoji and CJK but never position them at exact chunk boundaries (2048 bytes). A surrogate pair or `\r\n` landing exactly at a split point during insert or delete could expose bugs not caught by random stress testing.

**Fix:** Add tests that construct strings with multi-byte characters at positions 2046–2050 (near `maxChunkUTF8`), then insert/delete around those positions.

### 11. Stress test uses single seed with no failure logging

`testRandomOperationsMatchString` uses `SeededRNG(state: 42)` only. A failure won't log which seed/iteration failed.

**Fix:** Run multiple seeds (e.g., 0, 42, 12345, `UInt64.max`). On failure, log seed and iteration number in the `XCTFail` message.

## Minor

### 12. Line count tracked but not exposed

`Summary.lines` is computed and maintained but TextRope has no public `lineCount` property, unlike `utf16Count` and `utf8Count`.

**Fix:** `public var lineCount: Int { root.summary.lines }`

### 13. `Summary.of(_:)` does unnecessary work for empty strings

Not a bug — returns `.zero` correctly — but skipping the `withUTF8` closure for empty strings is a trivial optimization.

### 14. `nonisolated(unsafe)` root is a deliberate trade-off

`TextRope.root` is `nonisolated(unsafe)` for `Sendable` conformance. Concurrent mutations are undefined. This is acceptable for value-type COW semantics but should be documented.

### 15. `TextRope.Equatable` uses reference check optimization

`lhs.root === rhs.root || lhs.content == rhs.content` — the reference check is a fast path for COW copies. Semantically correct but calls O(n) `content` on the slow path. Consider whether this is acceptable for large ropes, or whether a tree-structural comparison would be better.

### 16. Fragile insert position logic at node boundaries

`TextRope+Insert.swift` uses `remaining < childUTF16 || i == node.children.count - 1` to select the target child. Works correctly but the fallthrough-to-last-child logic is subtle. Consider making the append-at-end case explicit.
