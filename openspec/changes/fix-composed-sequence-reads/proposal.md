## Why

`RopeBuffer.content(in:)` and `unsafeCharacter(at:)` — and their `SendableRopeBuffer` twins — return **wrong text** for documents containing regional-indicator (flag) runs. `TextRope.expandingWindow` (`Sources/TextRope/TextRope+ComposedSequences.swift:32-51`) materializes a ±128 UTF-16 unit window and runs `NSString.rangeOfComposedCharacterSequence(s)` inside it. UAX #29 GB12/GB13 pairs regional indicators by counting from the *start of the RI run*; a window that starts mid-run flips pairing parity, and the mispaired result sits strictly inside the window, so the existing edge-touch retry never fires:

```swift
let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)   // 🇩🇪 × 40
MutableStringBuffer(text).unsafeCharacter(at: 130)  // "🇩🇪"
RopeBuffer(text).unsafeCharacter(at: 130)           // "🇪🇩"  — wrong
```

This is DEF-002 — the only open defect that returns wrong content — affecting any document longer than 129 UTF-16 units that contains an RI run (136 of 400 offsets wrong at 100 flags). The same function also silently assumes `content(in:)` returns exactly `windowEnd - windowStart` code units (DEF-009); that assumption is false when a chunk boundary lands mid-scalar via the documented degenerate fallback at `Node+Split.swift:87-88`, which desynchronizes the `local` range from the materialized window.

The defect shipped untested because the specs never described composed-sequence reads: `openspec/specs/rope-buffer-conformance/spec.md:83-92` still describes `content(in:)` as plain substring extraction, and `openspec/specs/rope-buffer-drift/spec.md` has no composed-read drift requirement at all. The behavior change landed in `9570025` (archived `m2-rope-verification` fold) with only a tasks.md text correction. This change closes the behavioral hole and the spec hole together.

## What Changes

- **Parity-correct window anchor** — `expandingWindow` walks `windowStart` backward over the contiguous regional-indicator run (`U+1F1E6...U+1F1FF`) to the run start, so GB12/GB13 pairing inside the window matches pairing computed from document start. The walk is capped; a run longer than the cap falls back to full-document materialization (always correct, `O(n)`, pathological input only).
- **Window length invariant made explicit (DEF-009)** — the materialized window's length is checked against the requested span; a mismatch traps under `assert` in debug and falls back to full-document materialization in release, instead of silently computing `local` against a shifted window.
- **Regression tests, red first** — the 🇩🇪-run divergence repro at both the `TextRope` level (new `TextRopeComposedSequencesTests.swift`, currently untested API) and the buffer level; RI drift sweeps comparing `RopeBuffer` and `SendableRopeBuffer` against `MutableStringBuffer` across every offset of a long RI run; combining-mark and ZWJ-chain tests pinning that those remain unaffected; window-edge cases (offsets at the radius boundary, runs at document start/end, odd-length runs, lone RIs, RI adjacent to non-RI).
- **Spec deltas closing the coverage hole** — composed-sequence read semantics stated normatively at the rope level, the buffer-conformance content-access requirement corrected from "substring extraction" to composed-sequence expansion, and a composed-read drift requirement added, all with explicit UAX #29 GB12/GB13 scenarios.

No public API shape changes; `unsafeCharacter(at:)` and `content(in:)` keep their signatures and their `MutableStringBuffer`-matching contract — they simply start honoring it.

## Capabilities

### New Capabilities
<!-- None — this change corrects and extends existing capabilities. -->

### Modified Capabilities
- `rope-utf16-navigation`: adds the composed-character-sequence read contract (windowed reads MUST equal full-document `NSString` semantics, including GB12/GB13 regional-indicator pairing) and the window materialization length invariant
- `rope-buffer-conformance`: corrects the content-access requirement — `content(in:)` and `unsafeCharacter(at:)` return composed character sequences, not raw substrings
- `rope-buffer-drift`: adds composed-sequence read drift requirements covering RI runs, combining marks, ZWJ chains, and window edges for both `RopeBuffer` and `SendableRopeBuffer`

## Impact

- **Modified source:** `Sources/TextRope/TextRope+ComposedSequences.swift` (only file touched)
- **New test file:** `Tests/TextRopeTests/TextRopeComposedSequencesTests.swift` (the public composed-sequence API currently has zero direct tests)
- **Modified test file:** `Tests/TextBufferTests/RopeBufferDriftTests.swift` (extends the existing `MARK: - Composed Character Sequence Reads` block at `:179-214`)
- **Defects closed:** DEF-002 (critical), DEF-009 (medium)
- **Behavior change:** reads over RI runs now return correct text; no other read changes. `RopeBuffer` and `SendableRopeBuffer` both inherit the fix via `TextRope` — no buffer-layer edits needed.
- **Not addressed here:** DEF-011's read-performance regression (the RI walk adds work only when the window edge actually sits on an RI), DEF-001's mid-scalar chunk splits (DEF-009 is contained defensively, not root-caused), and the empty-range precondition bypass (DEF-004).

## Open Questions

1. **Cap value.** The proposal uses 4096 UTF-16 units (2048 consecutive regional indicators) as the backward-walk cap. It is a chosen round number, not a derived bound — should it instead be expressed in terms of `Node.maxChunkUTF8`, or made an internal tunable for tests to drive the fallback path cheaply?
2. **Cap-exceeded behavior.** Release builds fall back to full-document materialization. Should debug builds `assertionFailure` on that path (a 2048-flag run is almost certainly a fuzz/adversarial input), or stay silent so the fallback is exercised by tests without a trap?
3. **DEF-009 handling strength.** Assertion-plus-fallback is defensive containment. The real root cause is `Node+Split.swift:87-88` splitting mid-scalar (DEF-001 family). If DEF-001 lands first and makes the desync unreachable, does the fallback branch stay as belt-and-braces or become a hard `precondition`?
4. **Spec home for the composed API.** The composed-sequence contract is being added to `rope-utf16-navigation` because that capability owns `content(in:)`. It may deserve its own capability (`rope-composed-sequences`) — deferred, and entangled with DEF-006's canonical-spec cleanup.
5. **Fast path scope.** DEF-011 wants a non-surrogate/non-mark fast path for `unsafeCharacter(at:)`. Folding it in here would let the RI walk be skipped entirely for ASCII, but it changes the perf profile of a correctness fix. Kept out of scope — confirm that split.
