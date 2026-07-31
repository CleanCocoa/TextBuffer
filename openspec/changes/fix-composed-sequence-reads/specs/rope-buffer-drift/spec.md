## ADDED Requirements

### Requirement: Drift tests prove composed-sequence read equivalence with MutableStringBuffer

For every read scenario, calling `content(in:)` or `unsafeCharacter(at:)` on a `RopeBuffer` and on a `SendableRopeBuffer` holding the same content SHALL return exactly what `MutableStringBuffer` returns for the same call. The drift tests SHALL compare against `MutableStringBuffer` (Foundation as the oracle) rather than hardcoded expectations, except where a defect repro requires an absolute anchor. Both rope-backed buffer types MUST be asserted in the same test, since both delegate to the same `TextRope` read path.

#### Scenario: Surrogate halves
- **WHEN** `content(in:)` and `unsafeCharacter(at:)` are called at every offset of `"a😀b"`
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

#### Scenario: Combining marks
- **WHEN** `content(in:)` and `unsafeCharacter(at:)` are called at every offset of `"e\u{301}b"`
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

#### Scenario: Partial grapheme ranges on a multi-chunk rope
- **WHEN** reads target offsets around a composed sequence that straddles an internal chunk boundary
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

### Requirement: Drift tests prove regional indicator read equivalence with MutableStringBuffer

The drift suite SHALL cover UAX #29 GB12/GB13 regional indicator pairing across a run long enough to exceed any internal read window, at every offset — this is the coverage whose absence let a content-visible divergence ship.

#### Scenario: Flag run divergence repro
- **WHEN** both buffer kinds are created with `String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)` and `unsafeCharacter(at: 130)` is called
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return `"🇩🇪"`, identical to `MutableStringBuffer`

#### Scenario: Every offset of a long flag run
- **WHEN** both buffer kinds are created with a run of 100 identical flags (400 UTF-16 units) and every offset in `0..<400` is read via `unsafeCharacter(at:)`
- **THEN** every result SHALL equal the `MutableStringBuffer` result at that offset

#### Scenario: Ranged reads over a flag run
- **WHEN** `content(in:)` is called with ranges that sit inside, span, start mid-flag on a trail surrogate, and end inside a regional indicator run
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the same strings as `MutableStringBuffer`

#### Scenario: Flag run mixed with surrounding prose
- **WHEN** a flag run follows several hundred UTF-16 units of ASCII text, so a non-regional-indicator character sits immediately left of the run
- **THEN** reads at every offset in and around the run SHALL match `MutableStringBuffer`

#### Scenario: Odd-length and lone regional indicators
- **WHEN** the document contains an odd-length regional indicator run and a lone regional indicator between ASCII characters
- **THEN** reads at every affected offset SHALL match `MutableStringBuffer`

### Requirement: Drift tests pin the composed-sequence rules that are unaffected by windowing

Combining marks and ZWJ chains are locally decidable and are handled by the read window's edge-touch retry, not by regional indicator anchoring. The drift suite SHALL pin them at document positions far beyond any internal window radius, so that a future change to the windowing strategy surfaces as a failing test rather than as another silent content defect.

#### Scenario: ZWJ chain far into the document
- **WHEN** a document repeats a ZWJ emoji sequence (e.g. 👨‍👩‍👧‍👦) past offset 130 and reads target offsets inside those sequences
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the complete sequence, identical to `MutableStringBuffer`

#### Scenario: Combining marks far into the document
- **WHEN** a document repeats base-plus-combining-mark sequences past offset 130 and reads target the base or mark offsets
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the complete composed sequence, identical to `MutableStringBuffer`

#### Scenario: Emoji modifier sequence far into the document
- **WHEN** a document repeats an emoji-plus-skin-tone-modifier sequence past offset 130 and reads target any offset inside it
- **THEN** `RopeBuffer` and `SendableRopeBuffer` SHALL return the complete sequence, identical to `MutableStringBuffer`

### Requirement: Composed-read drift tests are cross-platform

The composed-sequence drift tests SHALL NOT require `#if os(macOS)` gating, consistent with the rest of `RopeBufferDriftTests` — `RopeBuffer`, `SendableRopeBuffer`, and `MutableStringBuffer` are all cross-platform types.

#### Scenario: No platform gate
- **WHEN** the composed-read drift tests are compiled
- **THEN** they SHALL NOT contain `#if os(macOS)` or any platform-conditional compilation
