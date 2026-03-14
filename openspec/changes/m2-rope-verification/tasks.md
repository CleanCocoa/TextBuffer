## 1. Test Infrastructure and Helpers

- [ ] 1.1 Create `Tests/TextRopeTests/TextRopeStressTests.swift` with `@testable import TextRope` and a `TextRopeStressTests: XCTestCase` class
- [ ] 1.2 Implement a deterministic seeded RNG conforming to `RandomNumberGenerator` for reproducible test sequences
- [ ] 1.3 Implement a `validateTreeStructure(_ rope: TextRope)` helper that recursively walks the tree and asserts: inner node summaries equal sum of children, leaf summaries equal `Summary.of(chunk)`, uniform leaf depth, B-tree child count bounds, chunk size bounds, and no `\r\n` split across chunk boundaries
- [ ] 1.4 Define a character pool constant containing ASCII, multi-byte Latin, emoji (surrogate pairs), CJK, and `\r\n` for random string generation
- [ ] 1.5 Implement `randomString(using rng:)` and `randomValidRange(in utf16Count:, using rng:)` helpers for generating random operations

## 2. Construction and Content Round-Trip Tests

- [ ] 2.1 Write tests for construction round-trip: empty string, sub-chunk string, single-chunk-sized string, multi-chunk string, and large string (100KB+) — verify `content` equals input and summary counts match
- [ ] 2.2 Write tests for encoding-specific round-trips: pure ASCII, multi-byte Latin (verify `utf8Count > utf16Count`), emoji (verify `utf16Count` accounts for surrogate pairs), CJK (verify `utf8Count` is 3× character count), and mixed-encoding text

## 3. COW Independence Tests

- [ ] 3.1 Write tests for COW independence: copy a multi-chunk rope, insert/delete/replace on the copy, verify original `content` is unchanged after each mutation type
- [ ] 3.2 Write test for COW under sustained mutation: copy a rope, apply 100 random mutations to the copy, assert original remains unchanged throughout

## 4. CRLF Invariant Edge-Case Tests

- [ ] 4.1 Write test for construction with `\r\n` at chunk boundary: build a string sized so `\r` would land at the last byte of a chunk, construct rope, verify no chunk ends with `\r` followed by a chunk starting with `\n`
- [ ] 4.2 Write tests for insert near CRLF at chunk boundary: insert before `\r`, at `\r`, between `\r` and `\n`, and after `\n` — verify invariant holds and line counts are correct after each
- [ ] 4.3 Write tests for delete/replace across CRLF pairs: delete just `\r`, delete just `\n`, replace spanning the pair — verify content correctness and line count consistency
- [ ] 4.4 Write test verifying line count consistency: after multiple CRLF insert/delete operations, assert `root.summary.lines` equals the count of `\n` in `rope.content`

## 5. Surrogate Pair Edge-Case Tests

- [ ] 5.1 Write tests for delete at surrogate boundaries: delete the full emoji from `"a🎉b"`, delete just `"a"` leaving emoji intact, delete range covering multiple emoji
- [ ] 5.2 Write tests for replace at surrogate boundaries: replace a single emoji with ASCII, replace a range spanning partial emoji sequences
- [ ] 5.3 Write test for emoji near chunk boundaries in a multi-chunk rope: construct a rope sized to place an emoji near a chunk boundary, then delete/replace targeting that region — verify no surrogate corruption

## 6. Repeated Single-Character Operation Tests

- [ ] 6.1 Write test for 1000 single-char inserts at position 0: verify final content is the reversed input and tree structure is valid
- [ ] 6.2 Write test for 1000 single-char appends at end: verify final content and tree balance
- [ ] 6.3 Write test for build-up then tear-down: insert 1000 chars one at a time, then delete one at a time from the end — verify empty rope at the end
- [ ] 6.4 Write test for alternating insert/delete: 2000 operations alternating between random single-char insert and random single-char delete, verify content matches oracle
- [ ] 6.5 Write test for 500 single emoji inserts at random positions: verify `utf16Count` is `1000`, content matches oracle, tree is valid

## 7. Stress Test (10K Random Operations)

- [ ] 7.1 Implement the main stress test: 10K random insert/delete/replace operations on TextRope + String oracle with seeded RNG, asserting content and summary equality after every operation
- [ ] 7.2 Add periodic tree structure validation (every 100 operations) and final validation at the end of the stress test
- [ ] 7.3 Add operation distribution assertion: verify the generated sequence contains all three operation types and no type exceeds 60%
- [ ] 7.4 Run full test suite with `swift test`, verify all tests pass with zero mismatches
