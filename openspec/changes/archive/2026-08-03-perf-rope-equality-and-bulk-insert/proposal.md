## Why

Two hot paths in `TextRope` do asymptotically more work than the data structure allows, both recorded against 0.9.1 in `DEFECTS.md`:

- **DEF-010** — `TextRope.==` (`Sources/TextRope/TextRope.swift:39-43`) falls straight from an identity check to `lhs.content == rhs.content`, materializing both ropes into fresh `String`s. TheArchive2 reaches this per edit event through `SendableRopeBuffer.comparator(.content)` (`Sources/TextBuffer/Buffer/SendableRopeBuffer.swift:226`) for echo suppression, so every keystroke allocates and walks two full documents even when the two ropes obviously differ in size. The root `Summary` already carries `utf8`, `utf16`, and `lines` for the whole rope in O(1); a mismatch there is proof of inequality.
- **DEF-011 (insert half)** — a large insert into a *non-root* leaf is quadratic. `insertIntoLeaf` (`TextRope+Insert.swift:61-68`) splices the whole string into the leaf and then splits off **one** chunk via `splitLeaf()`; the caller's loop (`TextRope+Insert.swift:37-44`) keeps calling `splitLeaf()` on the still-oversized tail, and each call copies the entire remaining tail into a new `String`. Inserting `n` bytes costs O(n² / maxChunkUTF8) byte copies. The root-leaf branch of the same function (`TextRope+Insert.swift:7-13`) already does the right thing: one `chunkLeaves` pass over the spliced chunk, then `buildTree`. The non-root path should mirror it.

Both are `Low` severity in the tracker but sit on per-keystroke and paste-sized paths, which is where they are felt.

## What Changes

- **Equality early-out.** `TextRope.==` gains a summary comparison between the existing identity fast path and the content materialization: if `lhs.root.summary != rhs.root.summary`, return `false` without materializing. Identical summaries still fall through to full content comparison — summaries are a lossy digest, not a hash of the text.
- **Single-pass bulk insert.** `insertIntoLeaf`'s overflow path re-chunks the spliced leaf in one pass with `TextRope.chunkLeaves(from:)` (the same helper the root-leaf branch and `TextRope.init(_:)` use), keeping the first chunk in the mutated leaf and returning the rest as siblings. The repeated-`splitLeaf` loop in `insertIntoNode` is removed; the existing n-way `splitInner()` overflow handling absorbs the wider sibling batch unchanged.
- **Equality test coverage.** The early-out needs rope-to-rope equality assertions before it can be trusted. Per the 2026-08-01 decisions, `fix-rope-cow-and-equality-coverage` lands first, closes DEF-005, and owns `Tests/TextRopeTests/TextRopeEqualityTests.swift` — including the "equal-length-but-different content" case it names as a guard for exactly this early-out. This change **extends** that file with the summary-specific cases (multi-leaf byte permutations, summary boundary cases) and rebases its `rope-core-types` Equatable delta as an increment on that change's archived delta, not a competing rewrite.

**Sequencing (2026-08-01 decisions).** This change lands **after** both:

1. `fix-rope-split-point` — which replaces `balancedSplitPoint` with `rebalancedChunks(in:)` and unifies `leafSplitPoint` and construction's `chunkEnd` onto the shared `leadingChunkEnd(in:)` helper. The bulk-insert re-chunk path here routes through `chunkLeaves`, and therefore through that shared helper, adopting ADR-012's grapheme-first chunk bounds (splits only at `Character` boundaries; `[minChunkUTF8, maxChunkUTF8]` whenever a conforming boundary exists; minimal-deviation under provable boundary starvation) by construction.
2. `fix-rope-cow-and-equality-coverage` — file ownership and delta baseline as above.

The agreed 0.10.0 order is: `fix-rope-split-point` → `fix-composed-sequence-reads` → `fix-rope-cow-and-equality-coverage` → **this change** → `docs-rope-disclosure` → `foundation-free-textrope`.

Both defects are marked `fixed` in `DEFECTS.md` and noted in `CHANGELOG.md` under the combined 0.10.0 release.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `rope-core-types`: equality gains a normative O(1) summary-based early-out with an explicit statement that differing summaries prove differing content while equal summaries prove nothing
- `rope-insert`: leaf overflow is re-chunked in a single pass, with the resulting chunks bounded per ADR-012 — within `[minChunkUTF8, maxChunkUTF8]` whenever a conforming `Character` boundary exists, minimal-deviation splits under provable boundary starvation (delta rebased on `fix-rope-split-point`'s "Leaf splitting on overflow" requirement)

## Impact

- **Modified sources:** `Sources/TextRope/TextRope.swift` (equality), `Sources/TextRope/TextRope+Insert.swift` (`insertIntoLeaf` return type and overflow path, `insertIntoNode` loop removal)
- **Extended tests:** `Tests/TextRopeTests/TextRopeEqualityTests.swift` (created and owned by `fix-rope-cow-and-equality-coverage`; this change adds cases); new cases in `Tests/TextRopeTests/TextRopeInsertTests.swift`
- **API surface:** unchanged — no public signature moves; `insertIntoLeaf` is `private`
- **Behavioral compatibility:** `==` keeps exact content-equality semantics. Chunk *boundaries* produced by a bulk insert change (see design decision 3) — leaf shape is not part of any public contract, and content, summaries, and all tree invariants (chunk bounds per ADR-012) are preserved
- **`Node.splitLeaf()`** loses both call sites but stays, pinned by `Tests/TextRopeTests/NodeTests.swift:28`
- **Defects closed:** DEF-010 and the insert half of DEF-011. DEF-005 is closed upstream by `fix-rope-cow-and-equality-coverage`
- **Coordination:** depends on `fix-rope-split-point` (shared `leadingChunkEnd(in:)` split helper, ADR-012 bounds, invariant-validator carve-out) and on `fix-rope-cow-and-equality-coverage` (`TextRopeEqualityTests.swift` ownership, Equatable delta baseline) — see What Changes for the full 0.10.0 order. No source-file overlap with `fix-composed-sequence-reads` (`TextRope+ComposedSequences.swift`) or `docs-rope-disclosure` (docs only); all changes edit `CHANGELOG.md` and `DEFECTS.md`, so expect textual conflicts there
- **Explicitly not closed:** the `unsafeCharacter(at:)` read regression, the other half of DEF-011 — see Non-Goals in `design.md`
