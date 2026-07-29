## Context

TextRope's structural and mutation operations are implemented across TASK-011 through TASK-017: Node/Summary types, COW infrastructure, construction, UTF-16 navigation, insert, delete, and replace. Each prior change (m2-rope-foundation, m2-rope-navigation, m2-rope-insert, etc.) included focused unit tests for its scope, but there is no comprehensive cross-cutting test suite that exercises the full API surface together. TASK-018 (Phase 8: Verification) is the final gate before buffer integration.

The rope's correctness invariants are defined in SPEC.md §4.3: summary consistency (every inner node's summary equals the sum of its children), the `\r\n` split invariant (never split between `\r` and `\n`), COW path-copying discipline, and the always-rooted property (ADR-006). The stress test must validate all of these under sustained random mutation.

## Goals / Non-Goals

**Goals:**
- Implement a randomized stress test that applies 10K random operations (insert, delete, replace) to both a `TextRope` and an equivalent `String`, asserting content and summary equality after each operation
- Cover construction round-trips at various sizes (empty, sub-chunk, single chunk, multi-chunk, very large)
- Cover content fidelity across encoding categories (ASCII, multi-byte Latin, emoji/surrogate pairs, CJK)
- Test `\r\n` invariant specifically at chunk boundaries under mutation pressure
- Test surrogate pair handling at range edges (delete/replace that starts or ends at a surrogate boundary)
- Test repeated single-character operations that force many splits and merges
- Verify COW independence under stress (mutate a copy, original unchanged)
- Verify tree rebalancing produces valid B-tree structure after sustained operations

**Non-Goals:**
- Performance benchmarking or timing thresholds (correctness only)
- RopeBuffer or Buffer-protocol-level testing (TASK-019/020)
- ManagedBuffer optimization path (ADR-005 upgrade path)
- Cursor or iterator types

## Decisions

### 1. Oracle-based stress testing pattern

The stress test uses a `String` as the oracle (reference implementation). Both `TextRope` and `String` receive identical random operations. After each operation, the test asserts:
- `rope.content == oracle` (content equality)
- `rope.utf16Count == oracle.utf16.count` (summary correctness for UTF-16)
- `rope.utf8Count == oracle.utf8.count` (summary correctness for UTF-8)

This is the same dual-execution pattern used by `assertUndoEquivalence` in TextBufferTesting (SPEC.md §4.4), adapted for the lower-level rope API.

**Why String as oracle:** `String` is the ground truth for Swift text semantics — character boundaries, UTF-16 counts, and grapheme cluster handling are all defined by `String`. Any divergence between `TextRope` and `String` is a bug in `TextRope`.

### 2. Random operation generation strategy

Operations are generated with a seeded random number generator for reproducibility. The distribution:
- ~40% inserts (random offset, random string from a character pool)
- ~30% deletes (random valid UTF-16 range)
- ~30% replaces (random valid UTF-16 range, random replacement string)

The character pool includes: ASCII, accented Latin (2-byte UTF-8), emoji with surrogate pairs (4-byte UTF-8), CJK characters (3-byte UTF-8), and `\r\n` pairs. This ensures all encoding paths are exercised.

Range generation must produce valid UTF-16 ranges (within `0...utf16Count`, not splitting surrogate pairs). The test generates ranges by picking two random offsets in the oracle's `utf16` view and clamping/ordering them.

**Seeded RNG:** Tests use a fixed seed logged at the start. On failure, the seed is reported so the exact sequence can be replayed. Swift's `RandomNumberGenerator` protocol with a custom deterministic generator enables this.

### 3. Edge-case test organization

Edge-case tests are separate from the stress test — they target specific invariants with handcrafted inputs:

- **`\r\n` at chunk boundaries:** Construct a rope where `\r` is the last byte of one chunk and `\n` would be the first byte of the next. Verify the split invariant keeps them together. Then insert/delete near that boundary and verify line counts remain correct.
- **Surrogate pairs at range edges:** Create a rope with emoji characters, then delete/replace ranges where the start or end offset falls at a surrogate boundary (between the high and low surrogate of an emoji). Verify the rope rounds to a valid character boundary or handles the edge correctly per the UTF-16 navigation spec.
- **Repeated single-char ops:** Insert 1000+ single characters one at a time, then delete them one at a time. This forces frequent leaf splits on insert and leaf merges on delete, stress-testing the rebalancing logic.

### 4. Tree structure validation helper

A recursive tree-walking helper validates internal invariants after operations:
- Every inner node's summary equals the sum of its children's summaries
- Every leaf's summary equals `Summary.of(chunk)`
- Every inner node has `minChildren...maxChildren` children (except possibly the root)
- Every leaf's chunk size is within `minChunkUTF8...maxChunkUTF8` (except possibly the last leaf or leaves in a small rope)
- Tree height is consistent (all leaves at the same depth)
- No `\r\n` split across chunk boundaries

This helper is called periodically (not after every operation in the 10K stress test, for performance — e.g., every 100 operations) and always at the end.

### 5. Single test file

All tests go in `Tests/TextRopeTests/TextRopeStressTests.swift` per TASK-018's file specification. The file contains one `XCTestCase` subclass with logical grouping via `// MARK:` sections for construction, content round-trip, edge cases, COW, and stress test.

## Risks / Trade-offs

- **Stress test execution time.** 10K operations with tree validation could be slow. → Mitigation: validate tree structure every 100 operations (not every 1), use a smaller iteration count for CI if needed, but keep 10K as the default.
- **Flaky tests from randomness.** A random seed that passes today could fail tomorrow if a new seed is chosen. → Mitigation: use a hardcoded default seed for deterministic CI runs. Add a separate test entry point that uses a random seed for exploratory runs.
- **Internal API access.** Tree structure validation requires access to `Node`, `Summary`, and tree internals which are `internal` to the TextRope module. → Mitigation: `@testable import TextRope` gives test targets access to internal types. This is standard XCTest practice.
- **Surrogate pair boundary behavior is implicit.** SPEC.md defines UTF-16 navigation but doesn't explicitly specify what happens when an offset falls between surrogate halves. → Mitigation: test the observed behavior and document it. The expected behavior is that `String.Index` rounding prevents mid-surrogate splits.
