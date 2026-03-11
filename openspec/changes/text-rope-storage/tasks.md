## 1. Rope Foundation (TASK-010 – 013)

- [ ] 1.1 Add `TextRope` library target and `TextRopeTests` test target to `Package.swift`; add `TextRope` dependency to `TextBuffer`; create `Sources/TextBuffer/Exports.swift` with `@_exported import TextRope`; verify `swift build` succeeds
- [ ] 1.2 Implement `TextRope.Summary` — `zero` constant, `add`, `subtract`, and `of(_: String)` factory; write `SummaryTests` covering ASCII, multi-byte, emoji (surrogate pairs), CJK, `\r\n` strings, and arithmetic round-trips
- [ ] 1.3 Implement `TextRope.Node` — fields (`summary`, `height`, `chunk`, `children`), named constants (`maxChildren`, `minChildren`, `maxChunkUTF8`, `minChunkUTF8`), `shallowCopy()`, `emptyLeaf()`, and `ensureUniqueChild(at:)`
- [ ] 1.4 Implement `TextRope` struct — `init()` (always-rooted empty leaf), `isEmpty`, `utf16Count`, `utf8Count`; annotate `root` as `nonisolated(unsafe)`; confirm empty-rope invariants in placeholder tests
- [ ] 1.5 Implement COW infrastructure — `ensureUnique()` on `TextRope` and `ensureUniqueChild(at:)` usage in `Node`; write initial `TextRopeCOWTests` covering shared-root identity after copy and helper-level uniqueness behavior. Full mutation-isolation verification is completed after public mutators exist in later insert/delete/replace tests.
- [ ] 1.6 Implement `TextRope.init(_ string: String)` — split string into chunks respecting `maxChunkUTF8` and the `\r\n` split invariant; build balanced initial tree from chunks
- [ ] 1.7 Implement `var content: String` (leaf concatenation) and `var utf16Count` / `utf8Count` via root summary; write `TextRopeConstructionTests` covering empty, single-char, ASCII, multi-byte, emoji, CJK, `\r\n`, chunk-boundary, and large-string round-trips

## 2. Core Operations (TASK-014 – 017)

- [ ] 2.1 Implement internal `findLeaf(utf16Offset:)` — tree descent accumulating `summary.utf16` per child; at leaf, translate remaining offset to `String.Index` via `chunk.utf16` view
- [ ] 2.2 Implement `func content(in utf16Range: NSRange) -> String` using the navigation from 2.1; write `TextRopeNavigationTests` covering single-leaf, multi-leaf, chunk boundaries, empty range, full range, emoji / surrogate pairs, and CJK
- [ ] 2.3 Implement `Node+Split` — split oversized leaf at the nearest valid UTF-8 boundary below `maxChunkUTF8`, adjusting the split point to avoid breaking a `\r\n` pair; return the new sibling node
- [ ] 2.4 Implement `TextRope+Insert` — `ensureUnique()`, COW descent to the target leaf, insert string at computed `String.Index`, call split if leaf exceeds `maxChunkUTF8`, propagate splits upward, update `summary` bottom-up
- [ ] 2.5 Write `TextRopeInsertTests` — insert at 0, end, middle; leaf-split trigger; cascading split that increases tree height; multi-byte boundary correctness; `\r\n` invariant regression; COW isolation; summary correctness after every case
- [ ] 2.6 Implement `Node+Merge` — merge an undersized leaf (below `minChunkUTF8`) with its nearest sibling; if combined size exceeds `maxChunkUTF8`, split the result instead; update summaries
- [ ] 2.7 Implement `TextRope+Delete` — `ensureUnique()`, COW descent to start and end leaves, remove content in range, merge undersized leaves, propagate merges upward, update `summary`; preserve always-rooted invariant (delete-all → empty leaf root)
- [ ] 2.8 Write `TextRopeDeleteTests` — delete within leaf, spanning leaves, spanning many leaves; merge trigger; cascading merge; delete all; multi-byte content; COW isolation; always-rooted after full delete; summary correctness
- [ ] 2.9 Implement `TextRope+Replace` as `delete(in:)` + `insert(_:at:)` composition; write `TextRopeReplaceTests` — shorter/longer/equal replacement, empty replacement (= delete), empty range (= insert), chunk-spanning range, COW isolation, summary correctness; verify behavioural equivalence against manual delete+insert

## 3. Rope Verification (TASK-018)

- [ ] 3.1 Write `TextRopeStressTests` scaffolding — random operation generator producing insert, delete, and replace actions with UTF-16 offsets and lengths clamped to current content size; apply each operation to both a `TextRope` and a `String` oracle; assert `rope.content == oracle` and `rope.utf16Count == oracle.utf16.count` after every operation
- [ ] 3.2 Run the stress test for 10,000 operations and fix any content mismatches or summary-drift failures; include operations at position 0, end, random middle, and with ASCII, multi-byte, and emoji payloads
- [ ] 3.3 Add targeted edge-case tests to the stress suite: `\r\n` pairs landing at chunk boundaries, surrogate pairs at range edges (verify no partial-surrogate extraction), repeated single-character inserts/deletes that trigger many splits and merges
- [ ] 3.4 Audit spec scenario coverage across all test files (`SummaryTests`, `TextRopeCOWTests`, `TextRopeConstructionTests`, `TextRopeNavigationTests`, `TextRopeInsertTests`, `TextRopeDeleteTests`, `TextRopeReplaceTests`, `TextRopeStressTests`); add any missing scenarios; confirm `swift test` passes with zero failures
