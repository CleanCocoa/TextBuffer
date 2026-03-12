## 1. RopeBuffer Type Skeleton

- [ ] 1.1 Create `Sources/TextBuffer/Buffer/RopeBuffer.swift` with `public final class RopeBuffer: Buffer, TextAnalysisCapable` stub — typealiases (`Range = NSRange`, `Content = String`), internal `var rope: TextRope`, `public var selectedRange: NSRange`, `public init(_ content: String = "")`, computed `content` and `range` properties. Verify it compiles with empty method bodies.
- [ ] 1.2 Add TextRope dependency to the TextBuffer target in `Package.swift` if not already present.

## 2. RopeBuffer Content Access

- [ ] 2.1 Implement `content(in:)` — validate range with `contains(range:)`, delegate to `rope.content(in:)`. Write test for valid subrange returning correct substring.
- [ ] 2.2 Implement `unsafeCharacter(at:)` — delegate to rope content extraction for a single character at UTF-16 offset.
- [ ] 2.3 Implement `lineRange(for:)` — validate range, delegate to `(self.content as NSString).lineRange(for:)`. Write test for line range expansion.
- [ ] 2.4 Implement `modifying(affectedRange:_:)` — validate range, execute block. Write tests for valid and invalid ranges.

## 3. RopeBuffer Edit Operations with Selection Adjustment

- [ ] 3.1 Implement `insert(_:at:)` — validate location, delegate to `rope.insert(_:at:)`, adjust `selectedRange` via `shifted(by: location <= selectedRange.location ? content.utf16.count : 0)`. Write tests: insert before/at/after insertion point, insert before/at/within/after selection, out-of-range error.
- [ ] 3.2 Implement `delete(in:)` — validate range, delegate to `rope.delete(in:)`, adjust `selectedRange` via `subtract(deletedRange)`. Write tests: delete before/after/across insertion point, delete within/overlapping/encompassing selection, out-of-range error.
- [ ] 3.3 Implement `replace(range:with:)` — validate range, delegate to `rope.replace(range:with:)`, adjust `selectedRange` via `subtracting(replacementRange).shifted(by:)`. Write tests: replace before/overlapping/after selection, out-of-range error.

## 4. RopeBuffer Finishing Touches

- [ ] 4.1 Add `@available(*, unavailable) extension RopeBuffer: @unchecked Sendable {}` to match MutableStringBuffer's Sendable opt-out pattern.
- [ ] 4.2 Add `CustomStringConvertible` conformance with guillemet/caret notation matching `MutableStringBuffer.description`.
- [ ] 4.3 Verify `wordRange(for:)` works via the `TextAnalysisCapable` protocol extension default — write a test exercising word range expansion.

## 5. RopeBuffer Drift Tests — Insert Scenarios

- [ ] 5.1 Create `Tests/TextBufferTests/RopeBufferDriftTests.swift` with helper: `bufferPair(_ content: String, selectedRange: NSRange) -> (rope: RopeBuffer, msb: MutableStringBuffer)` that creates both with identical initial state. Add `assertBehaviorMatch` comparing `content` and `selectedRange`. No `#if os(macOS)` gating.
- [ ] 5.2 Write drift tests for insert with insertion point: before, at, after insertion point — assert equivalence after each.
- [ ] 5.3 Write drift tests for insert with selection: before selection, at selection start, within selection, at selection end, after selection — assert equivalence after each.

## 6. RopeBuffer Drift Tests — Delete Scenarios

- [ ] 6.1 Write drift tests for delete with insertion point: before, after, across insertion point.
- [ ] 6.2 Write drift tests for delete with selection: within, overlapping start, overlapping end, entire, encompassing, before, after selection.

## 7. RopeBuffer Drift Tests — Replace and Sequential Scenarios

- [ ] 7.1 Write drift tests for replace: before selection, overlapping selection, after selection.
- [ ] 7.2 Write drift test for sequential inserts with selection — apply 3 sequential inserts and assert equivalence after each.
- [ ] 7.3 Write drift test for mixed insert/delete operations — apply a sequence of mixed ops and assert equivalence after each step.
