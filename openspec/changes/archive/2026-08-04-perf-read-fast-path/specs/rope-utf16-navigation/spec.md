## ADDED Requirements

### Requirement: Simple-cluster point reads take a bounded fast path

`composedCharacterSequence(at utf16Offset:)` SHALL answer without materializing an expansion window when the code units at `utf16Offset - 1`, `utf16Offset`, and `utf16Offset + 1` — those that exist; a missing neighbor at a document edge counts as safe — are all printable ASCII (`0x20...0x7E`). In that case the implementation MUST inspect the rope through at most **one** block read of at most three code units (a single tree descent via the `package`-scoped `utf16CodeUnits(in:)`) and return the single-code-unit string directly, with no window materialization and no `NSString` bridging.

The fast path MUST NOT change any observable result: for every rope and every in-bounds offset, the returned string MUST remain identical to the result of applying `NSString.rangeOfComposedCharacterSequence(at:)` to the rope's **entire** content and extracting the resulting range — the same contract the windowed path satisfies. The safe set is exactly printable ASCII: it contains no surrogate halves, no combining marks, no ZWJ, no variation selectors, no regional indicators, and no CR, LF, or other control characters, so a qualifying unit with qualifying neighbors is provably a complete, self-contained composed sequence. Whenever **any** inspected unit falls outside the safe set — including CR and LF, whose composed-sequence treatment is the documented divergence point between grapheme clustering and `NSString` semantics — the implementation SHALL fall through to the windowed expansion path with behavior unchanged.

The per-call cost of the fast path MUST be independent of document size apart from the O(log n) tree descent: it SHALL NOT scale with the document's length, the distance of the offset from the document start, or the rope's leaf count.

#### Scenario: Fast-path result is indistinguishable from full-document expansion
- **WHEN** `composedCharacterSequence(at: k)` is called for every `k` in `0..<utf16Count` on a document interleaving printable ASCII with emoji, combining marks, ZWJ chains, CRLF pairs, and regional indicator runs
- **THEN** every result SHALL equal `(rope.content as NSString).substring(with: (rope.content as NSString).rangeOfComposedCharacterSequence(at: k))`
- **AND** no offset SHALL reveal which internal path produced the answer

#### Scenario: Printable ASCII interior read performs at most one block read
- **WHEN** `composedCharacterSequence(at: k)` is called where the units at `k - 1`, `k`, and `k + 1` are all printable ASCII
- **THEN** the result SHALL be the single-code-unit string at `k`
- **AND** the implementation SHALL perform at most one block read of at most three code units, materializing no expansion window and bridging no `NSString`

#### Scenario: Document edges count as safe neighbors
- **WHEN** `composedCharacterSequence(at: 0)` or `composedCharacterSequence(at: utf16Count - 1)` is called and every unit that exists among the offset and its neighbors is printable ASCII
- **THEN** the fast path SHALL apply, treating the absent neighbor as safe, and the result SHALL equal full-document expansion

#### Scenario: CR and LF fall through to the windowed path
- **WHEN** `composedCharacterSequence(at:)` targets a CR or LF offset, or an offset whose neighbor is CR or LF — e.g. any offset of `"a\r\nb"`
- **THEN** the implementation SHALL take the windowed expansion path
- **AND** the result SHALL be unchanged from the pre-fast-path behavior, preserving the pinned `NSString` semantics (`"\r"` at the `\r` offset, not the Swift grapheme cluster `"\r\n"`)

#### Scenario: Offsets adjacent to non-ASCII fall through
- **WHEN** `composedCharacterSequence(at: k)` targets a printable ASCII unit whose preceding or following unit is outside `0x20...0x7E` — e.g. the `b` in `"a😀b"` or the base ASCII letter directly before a combining mark
- **THEN** the implementation SHALL fall through to the windowed expansion path
- **AND** the result SHALL equal full-document expansion

#### Scenario: Per-call cost is independent of document size
- **WHEN** the same fixed batch of `composedCharacterSequence(at:)` calls, at offsets spread proportionally across the document, is timed on a 1 MiB and on a 4 MiB all-ASCII rope
- **THEN** the measured time ratio SHALL stay well below the ≈4× that document-proportional work would predict, bounded consistent with per-call-constant cost plus the O(log n) descent
