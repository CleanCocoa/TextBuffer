---
status: accepted
date: 2026-08-01
title: "ADR-012: Grapheme-first chunk bounds with provable boundary starvation"
---

# ADR-012: Grapheme-first chunk bounds with provable boundary starvation

## Context

TextRope leaves carry chunk-size bounds of `minChunkUTF8 = 1024` and `maxChunkUTF8 = 2048` bytes. The DEF-001 investigation (see DEFECTS.md) proved the bounds cannot be absolute if splits are restricted to `Character` (grapheme cluster) boundaries: for a 2049-byte chunk shaped `1023×'a' + 😀 + 1022×'b'`, the only grapheme boundaries near the midpoint sit at offsets 1023 and 1027, so no two-leaf shape satisfies both bounds, and `3 × minChunkUTF8 > 2049` rules out three leaves.

Two coherent regimes exist:

1. **Byte-strict**: bounds are absolute; splits may fall inside a grapheme cluster at Unicode-scalar boundaries when no conforming cluster boundary exists. Content round-trips (Swift index rounding), but reads must reassemble clusters that span chunk seams.
2. **Grapheme-first**: splits only ever occur at `Character` boundaries; byte bounds soften where cluster geometry makes them unsatisfiable.

The 0.9.0 implementation satisfied neither regime coherently: its fallback walked backward from the midpoint ignoring the legal window entirely, producing both oversized (2049-byte) and undersized (1023-byte, stable fixed point) leaves even when conforming splits existed.

## Decision

Grapheme clusters are the primitive users care about; byte counts are an implementation budget. Therefore:

- Splits occur **only at `Character` boundaries**. The `\r\n` never-split rule is thereby absolute (CRLF is a single `Character`) rather than a special case.
- Chunk byte bounds `[minChunkUTF8, maxChunkUTF8]` **MUST hold whenever a conforming boundary exists**.
- Under **boundary starvation** — no `Character` boundary yields a conforming split — the nearest-boundary **minimal-deviation** split is taken. A single cluster larger than `maxChunkUTF8` occupies one whole-cluster leaf of whatever size it needs.
- **Starvation is provable per leaf**, so the tree validator stays exact: a leaf violating the bounds must demonstrably have no conforming boundary available (enumerate its cluster boundaries; verify none produces a conforming split, including via merge with a neighbor). No fuzzy tolerance constant exists.
- **Merges accept deviation-sized leaves without retrying**: a leaf that is out of bounds under proven starvation does not re-trigger rebalancing on subsequent operations.

## Consequences

- Deviation is bounded by the longest grapheme cluster in the document — single-digit bytes for real-world text (flags 8 B, ZWJ family emoji ~25 B), so tree height and asymptotics are unaffected.
- A crafted pathological cluster (Zalgo, long ZWJ chains) larger than `maxChunkUTF8` produces one oversized leaf: still correct, locally more expensive to edit, accepted.
- Because chunk seams can never fall inside a cluster, `content(in:)` can never mis-slice mid-cluster; the composed-sequence read path's window-length defense (DEF-009) graduates from debug-assert-plus-fallback to a hard precondition.
- `NodeTests`' split-point expectation of 1023 for the starved 2049-byte layout is correct by this rule (minimal shortfall) and is renamed to state that reason rather than pin an anomaly.
- Rejected alternative: byte-strict with scalar-boundary escape. It keeps the validator a pure byte predicate but forces every read path to handle cluster reassembly forever, trading a decidable structural exception for a permanent semantic complication where users actually look.
