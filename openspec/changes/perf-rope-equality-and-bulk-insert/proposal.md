## Why

Two hot paths in `TextRope` do asymptotically more work than the data structure allows, both recorded against 0.9.1 in `DEFECTS.md`:

- **DEF-010** — `TextRope.==` (`Sources/TextRope/TextRope.swift:39-43`) falls straight from an identity check to `lhs.content == rhs.content`, materializing both ropes into fresh `String`s. TheArchive2 reaches this per edit event through `SendableRopeBuffer.comparator(.content)` (`Sources/TextBuffer/Buffer/SendableRopeBuffer.swift:226`) for echo suppression, so every keystroke allocates and walks two full documents even when the two ropes obviously differ in size. The root `Summary` already carries `utf8`, `utf16`, and `lines` for the whole rope in O(1); a mismatch there is proof of inequality.
- **DEF-011 (insert half)** — a large insert into a *non-root* leaf is quadratic. `insertIntoLeaf` (`TextRope+Insert.swift:61-68`) splices the whole string into the leaf and then splits off **one** chunk via `splitLeaf()`; the caller's loop (`TextRope+Insert.swift:37-44`) keeps calling `splitLeaf()` on the still-oversized tail, and each call copies the entire remaining tail into a new `String`. Inserting `n` bytes costs O(n² / maxChunkUTF8) byte copies. The root-leaf branch of the same function (`TextRope+Insert.swift:7-13`) already does the right thing: one `chunkLeaves` pass over the spliced chunk, then `buildTree`. The non-root path should mirror it.

Both are `Low` severity in the tracker but sit on per-keystroke and paste-sized paths, which is where they are felt.

## What Changes

- **Equality early-out.** `TextRope.==` gains a summary comparison between the existing identity fast path and the content materialization: if `lhs.root.summary != rhs.root.summary`, return `false` without materializing. Identical summaries still fall through to full content comparison — summaries are a lossy digest, not a hash of the text.
- **Single-pass bulk insert.** `insertIntoLeaf`'s overflow path re-chunks the spliced leaf in one pass with `TextRope.chunkLeaves(from:)` (the same helper the root-leaf branch and `TextRope.init(_:)` use), keeping the first chunk in the mutated leaf and returning the rest as siblings. The repeated-`splitLeaf` loop in `insertIntoNode` is removed; the existing n-way `splitInner()` overflow handling absorbs the wider sibling batch unchanged.
- **Equality test coverage.** `TextRope: Equatable` currently has no rope-to-rope assertions anywhere (DEF-005), which is exactly the coverage the early-out needs before it can be trusted. This change adds that coverage as its regression guard.

  **Collision:** the sibling change `fix-rope-cow-and-equality-coverage` also claims DEF-005 and also creates `Tests/TextRopeTests/TextRopeEqualityTests.swift` — including, explicitly, an "equal-length-but-different content" case named as a guard for "any future summary-based early-out per DEF-010". Whichever change lands first owns the file; the second merges its cases in rather than recreating it. This change cannot ship its early-out without those assertions, so if `fix-rope-cow-and-equality-coverage` lands first, tasks 1.1-1.3 reduce to auditing the existing file and adding only the missing summary-specific cases.

Both defects are marked `fixed` in `DEFECTS.md` and noted in `CHANGELOG.md` under the upcoming patch release.

## Capabilities

### New Capabilities
<!-- None -->

### Modified Capabilities
- `rope-core-types`: equality gains a normative O(1) summary-based early-out with an explicit statement that differing summaries prove differing content while equal summaries prove nothing
- `rope-insert`: leaf overflow is re-chunked in a single pass, with the resulting chunks bounded by `[minChunkUTF8, maxChunkUTF8]`

## Impact

- **Modified sources:** `Sources/TextRope/TextRope.swift` (equality), `Sources/TextRope/TextRope+Insert.swift` (`insertIntoLeaf` return type and overflow path, `insertIntoNode` loop removal)
- **New tests:** `Tests/TextRopeTests/TextRopeEqualityTests.swift`; new cases in `Tests/TextRopeTests/TextRopeInsertTests.swift`
- **API surface:** unchanged — no public signature moves; `insertIntoLeaf` is `private`
- **Behavioral compatibility:** `==` keeps exact content-equality semantics. Chunk *boundaries* produced by a bulk insert change (see design decision 3 and the open question) — leaf shape is not part of any public contract, and content, summaries, and all tree invariants are preserved
- **`Node.splitLeaf()`** loses both call sites but stays, pinned by `Tests/TextRopeTests/NodeTests.swift:28`
- **Defects closed:** DEF-010 and the insert half of DEF-011; DEF-005 as a side effect of the equality tests, unless `fix-rope-cow-and-equality-coverage` closes it first
- **Coordination:** overlaps `fix-rope-cow-and-equality-coverage` on `Tests/TextRopeTests/TextRopeEqualityTests.swift` and DEF-005 (see What Changes). No source-file overlap with the other active changes — `fix-composed-sequence-reads` touches `TextRope+ComposedSequences.swift`, `docs-rope-disclosure` touches docs only; both edit `CHANGELOG.md` and `DEFECTS.md`, so expect textual conflicts there
- **Explicitly not closed:** the `unsafeCharacter(at:)` read regression, the other half of DEF-011 — see Non-Goals in `design.md`
