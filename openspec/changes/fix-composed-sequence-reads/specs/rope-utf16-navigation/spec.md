## ADDED Requirements

### Requirement: Composed character sequence reads match full-document NSString semantics

`TextRope` SHALL provide `composedCharacterSequences(in utf16Range: NSRange) -> String` and `composedCharacterSequence(at utf16Offset: Int) -> String`. For every rope and every in-bounds argument, the returned string MUST be identical to the result of applying `NSString.rangeOfComposedCharacterSequences(for:)` / `NSString.rangeOfComposedCharacterSequence(at:)` to the rope's **entire** content and extracting the resulting range. The result MUST NOT depend on the rope's internal chunking, tree shape, or on any window size used internally to avoid materializing the whole document.

#### Scenario: Read equals full-document expansion at every offset
- **WHEN** `composedCharacterSequence(at: k)` is called for any `k` in `0..<utf16Count`
- **THEN** the result SHALL equal `(rope.content as NSString).substring(with: (rope.content as NSString).rangeOfComposedCharacterSequence(at: k))`

#### Scenario: Read is independent of tree shape
- **WHEN** two ropes hold identical content but were built differently (single leaf versus many leaves, e.g. via bulk init versus incremental inserts)
- **THEN** `composedCharacterSequence(at: k)` SHALL return the same string from both for every `k`

#### Scenario: Surrogate pair halves resolve to the whole character
- **WHEN** `composedCharacterSequence(at:)` is called at either the lead or the trail surrogate offset of a non-BMP character such as 😀
- **THEN** the result SHALL be the complete character

#### Scenario: Combining mark sequences are returned whole
- **WHEN** the rope contains base-plus-combining-mark sequences (e.g. `e\u{301}`) and a read targets the base or the mark offset
- **THEN** the result SHALL be the complete composed sequence

#### Scenario: ZWJ emoji chains are returned whole
- **WHEN** the rope contains a ZWJ emoji sequence (e.g. 👨‍👩‍👧‍👦) and a read targets any offset inside it
- **THEN** the result SHALL be the complete sequence, regardless of how far into the document the sequence sits

### Requirement: Regional indicator pairing follows UAX #29 GB12/GB13 from the run start

Reads over regional indicator characters (`U+1F1E6...U+1F1FF`) MUST pair them per UAX #29 GB12/GB13 — counting from the start of the maximal contiguous regional indicator run, exactly as a full-document `NSString` expansion would. An internal read window MUST NOT begin strictly inside a regional indicator run; when a computed window start falls inside such a run, the implementation SHALL extend the window backward to the start of that run so that pairing parity inside the window matches pairing parity computed from the document start.

#### Scenario: Flag read beyond the internal window radius
- **WHEN** a rope holds `String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)` (🇩🇪 × 40, 160 UTF-16 units) and `composedCharacterSequence(at: 130)` is called
- **THEN** the result SHALL be `"🇩🇪"`
- **AND** it SHALL NOT be the mispaired `"🇪🇩"`

#### Scenario: Every offset of a long flag run reads correctly
- **WHEN** a rope holds a run of 100 identical flags (400 UTF-16 units) and `composedCharacterSequence(at: k)` is called for every `k` in `0..<400`
- **THEN** every result SHALL equal the full-document `NSString` expansion at that offset

#### Scenario: Regional indicator run beginning at document start
- **WHEN** the regional indicator run starts at offset 0 and a read targets an offset inside it
- **THEN** the result SHALL match full-document expansion, with the window start clamped to 0

#### Scenario: Odd-length regional indicator run
- **WHEN** the run contains an odd number of regional indicators, leaving a final unpaired regional indicator
- **THEN** reads at every offset in the run — including the unpaired trailing one — SHALL match full-document expansion

#### Scenario: Regional indicator run bounded by non-regional-indicator text
- **WHEN** a flag run is preceded and followed by ASCII text
- **THEN** pairing SHALL restart at the run start, and reads at every offset SHALL match full-document expansion

#### Scenario: Lone regional indicator
- **WHEN** a single regional indicator appears between non-regional-indicator characters
- **THEN** a read at that offset SHALL return just that regional indicator, matching full-document expansion

#### Scenario: Read range starting on a trail surrogate inside a flag
- **WHEN** `composedCharacterSequences(in:)` is called with a range whose location is the trail surrogate offset of a regional indicator inside a run
- **THEN** the returned string SHALL be the correctly paired composed sequences, matching full-document expansion

#### Scenario: Regional indicator run longer than the backward-walk cap
- **WHEN** a contiguous regional indicator run is longer than the implementation's backward-walk cap
- **THEN** the implementation SHALL fall back to full-document expansion
- **AND** the returned string SHALL still match full-document `NSString` semantics

### Requirement: Materialized read window length matches the requested span

Any internal window materialized for a composed-sequence boundary search MUST contain exactly the number of UTF-16 code units requested for it. The implementation SHALL NOT assume this silently: it MUST verify the materialized length against the requested span before computing window-relative ranges, and on mismatch MUST NOT compute a window-relative range against the desynchronized window. Debug builds SHALL trap on mismatch; release builds SHALL fall back to full-document expansion so the returned text remains consistent with the rope's `content`.

#### Scenario: Window length matches in normal operation
- **WHEN** a composed-sequence read materializes an internal window of `n` requested UTF-16 code units on a rope with well-formed chunk boundaries
- **THEN** the materialized window SHALL contain exactly `n` UTF-16 code units

#### Scenario: Mismatch is detected rather than assumed away
- **WHEN** a chunk boundary falls mid-scalar and the materialized window's UTF-16 length differs from the requested span
- **THEN** the implementation SHALL NOT index the window with a range derived from the requested span
- **AND** the read SHALL either trap (debug) or return the full-document expansion result (release)
