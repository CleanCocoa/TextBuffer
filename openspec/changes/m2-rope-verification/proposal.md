## Why

TextRope's core operations (construction, insert, delete, replace, COW, navigation) are implemented across TASK-011 through TASK-017, but lack a comprehensive verification suite. TASK-018 is the verification gate: a broad test suite that exercises construction at various sizes, content round-trips across encodings, mutation edge cases, COW independence, summary correctness, the `\r\n` split invariant, surrogate pair handling, rebalancing, and a 10K random-operation stress test against a String oracle. Without this gate, rope correctness is unproven and the buffer integration phase (TASK-019/020) cannot proceed with confidence.

## What Changes

- Add a comprehensive stress testing framework that applies 10K random insert/delete/replace operations to both `TextRope` and an equivalent `String` oracle, asserting content and summary equality after each operation
- Add targeted edge-case tests for `\r\n` at chunk boundaries, surrogate pairs at range edges, and repeated single-character operations that trigger many splits and merges
- Cover construction (empty, small, exactly-one-chunk, multi-chunk, very large), content round-trip (ASCII, multi-byte, emoji, CJK), COW independence, and rebalancing verification

Corresponds to **TASK-018** in the master roadmap (Milestone 2, Phase 8: Verification).

## Capabilities

### New Capabilities
- `rope-stress-testing`: Randomized stress testing framework — 10K random insert/delete/replace operations applied to both TextRope and String oracle, asserting content and summary equality after each operation
- `rope-edge-cases`: Targeted edge-case testing for `\r\n` at chunk boundaries, surrogate pairs at range edges, repeated single-char operations that trigger many splits/merges

### Modified Capabilities
<!-- No existing specs to modify -->

## Impact

- **New files:** `Tests/TextRopeTests/TextRopeStressTests.swift`
- **Dependencies:** Requires TASK-013 through TASK-017 to be complete (construction, COW, navigation, insert, delete, replace)
- **API surface:** No API changes — this is a pure test change
- **Unlocks:** TASK-019 (RopeBuffer), TASK-020 (drift tests) — the buffer integration phase depends on proven rope correctness
