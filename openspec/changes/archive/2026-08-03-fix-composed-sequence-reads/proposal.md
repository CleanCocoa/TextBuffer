## Why

`RopeBuffer.content(in:)` and `unsafeCharacter(at:)` — and their `SendableRopeBuffer` twins — return **wrong text** for documents containing regional-indicator (flag) runs. `TextRope.expandingWindow` (`Sources/TextRope/TextRope+ComposedSequences.swift:32-51`) materializes a ±128 UTF-16 unit window and runs `NSString.rangeOfComposedCharacterSequence(s)` inside it. UAX #29 GB12/GB13 pairs regional indicators by counting from the *start of the RI run*; a window that starts mid-run flips pairing parity, and the mispaired result sits strictly inside the window, so the existing edge-touch retry never fires:

```swift
let text = String(repeating: "\u{1F1E9}\u{1F1EA}", count: 40)   // 🇩🇪 × 40
MutableStringBuffer(text).unsafeCharacter(at: 130)  // "🇩🇪"
RopeBuffer(text).unsafeCharacter(at: 130)           // "🇪🇩"  — wrong
```

This is DEF-002 — the only open defect that returns wrong content — affecting any document longer than 129 UTF-16 units that contains an RI run (136 of 400 offsets wrong at 100 flags). The same function also silently assumes `content(in:)` returns exactly `windowEnd - windowStart` code units (DEF-009). Under ADR-012's grapheme-first chunk bounds — established by `fix-rope-split-point`, which this change sequences after — a chunk seam can never fall inside a `Character`, so that assumption is a structural invariant; this change stops assuming it silently and enforces it with a hard `precondition`. Finally, the read paths inherited DEF-004: the empty-range early returns in `content(in:)` (`TextRope+Navigation.swift:30`) and `composedCharacterSequences(in:)` (`TextRope+ComposedSequences.swift:9`) run *before* the bounds preconditions, so `content(in: NSRange(location: 500, length: 0))` on a 5-character rope silently returns `""` instead of trapping — violating `openspec/specs/rope-utf16-navigation/spec.md:75-77`.

The defect shipped untested because the specs never described composed-sequence reads: `openspec/specs/rope-buffer-conformance/spec.md:83-92` still describes `content(in:)` as plain substring extraction, and `openspec/specs/rope-buffer-drift/spec.md` has no composed-read drift requirement at all. The behavior change landed in `9570025` (archived `m2-rope-verification` fold) with only a tasks.md text correction. This change closes the behavioral hole and the spec hole together.

## What Changes

- **Parity-correct window anchor** — `expandingWindow` walks `windowStart` backward over the contiguous regional-indicator run (`U+1F1E6...U+1F1FF`) to the run start, so GB12/GB13 pairing inside the window matches pairing computed from document start. The walk is capped at a fixed 4,096 UTF-16 units (2,048 regional indicators) — deliberately not derived from `Node.maxChunkUTF8`, since the cap bounds RI-run walking, a property of the text, not of chunk geometry. A run longer than the cap falls back **silently** to full-document materialization (always correct, `O(n)`, pathological input only) — no `assertionFailure`, so the fallback is an ordinary, testable path.
- **Window length invariant enforced as a `precondition` (DEF-009)** — the materialized window's length is checked against the requested span with a hard `precondition` in all build configurations. Under ADR-012 a chunk seam can never fall inside a `Character`, so a mismatch can only mean a broken rope-internal invariant; no text computed against a shifted window is correct to return. This supersedes the earlier debug-assert-plus-release-fallback design — the fallback branch would guard a structurally unreachable state.
- **Out-of-bounds trap for zero-length ranges (DEF-004)** — the bounds preconditions move *before* the empty-range early returns in `content(in:)` (`TextRope+Navigation.swift:30`) and `composedCharacterSequences(in:)` (`TextRope+ComposedSequences.swift:9`), so a zero-length range at a past-end, negative, or `NSNotFound` location traps instead of silently returning `""`. In-bounds empty ranges keep returning `""`. This is a 0.10.0 behavior tightening, covered by process-exit tests.
- **Regression tests, red first** — the 🇩🇪-run divergence repro at both the `TextRope` level (new `TextRopeComposedSequencesTests.swift`, currently untested API) and the buffer level; RI drift sweeps comparing `RopeBuffer` and `SendableRopeBuffer` against `MutableStringBuffer` across every offset of a long RI run; combining-mark and ZWJ-chain tests pinning that those remain unaffected; window-edge cases (offsets at the radius boundary, runs at document start/end, odd-length runs, lone RIs, RI adjacent to non-RI); a cap-exceeding RI run driving the silent full-document fallback; and process-exit tests for the zero-length out-of-bounds trap.
- **Spec deltas closing the coverage hole** — composed-sequence read semantics stated normatively at the rope level, the buffer-conformance content-access requirement corrected from "substring extraction" to composed-sequence expansion, and a composed-read drift requirement added, all with explicit UAX #29 GB12/GB13 scenarios — plus the window-length precondition, the silent cap fallback, and the zero-length out-of-bounds trap.

No public API shape changes; `unsafeCharacter(at:)` and `content(in:)` keep their signatures and their `MutableStringBuffer`-matching contract — they simply start honoring it. The one behavior tightening: zero-length out-of-range reads now trap where they silently returned `""` (DEF-004, 0.10.0).

## Capabilities

### New Capabilities
<!-- None — this change corrects and extends existing capabilities. -->

### Modified Capabilities
- `rope-utf16-navigation`: adds the composed-character-sequence read contract (windowed reads MUST equal full-document `NSString` semantics, including GB12/GB13 regional-indicator pairing), the fixed 4,096-unit backward-walk cap with silent full-document fallback, the window materialization length invariant as a hard precondition (per ADR-012), and the out-of-bounds trap for zero-length ranges (DEF-004) on `content(in:)` and the composed-sequence APIs — the composed API stays under this capability rather than gaining its own (resolved 2026-08-01)
- `rope-buffer-conformance`: corrects the content-access requirement — `content(in:)` and `unsafeCharacter(at:)` return composed character sequences, not raw substrings
- `rope-buffer-drift`: adds composed-sequence read drift requirements covering RI runs, combining marks, ZWJ chains, and window edges for both `RopeBuffer` and `SendableRopeBuffer`

## Impact

- **Sequencing:** this change depends on `fix-rope-split-point` landing first — ADR-012's grapheme-first chunk bounds (no chunk seam inside a `Character`) are what make the DEF-009 window-length check a legitimate hard `precondition`. It implements second in the 0.10.0 order recorded in DEFECTS.md.
- **Modified source:** `Sources/TextRope/TextRope+ComposedSequences.swift`; `Sources/TextRope/TextRope+Navigation.swift` (DEF-004 only: bounds preconditions moved before the empty-range early return in `content(in:)`)
- **New test file:** `Tests/TextRopeTests/TextRopeComposedSequencesTests.swift` (the public composed-sequence API currently has zero direct tests)
- **Modified test files:** `Tests/TextBufferTests/RopeBufferDriftTests.swift` (extends the existing `MARK: - Composed Character Sequence Reads` block at `:179-214`); `Tests/TextRopeTests/TextRopeNavigationPreconditionTests.swift` (DEF-004 process-exit tests for zero-length out-of-bounds reads)
- **Defects closed:** DEF-002 (critical), DEF-009 (medium — closed structurally by ADR-012 via `fix-rope-split-point`, enforced here), DEF-004 (medium)
- **Behavior change:** reads over RI runs now return correct text, and zero-length out-of-range reads trap instead of silently returning `""` (0.10.0 behavior tightening); no other read changes. `RopeBuffer` and `SendableRopeBuffer` both inherit the fixes via `TextRope` — no buffer-layer edits needed (the buffers already guard ranges via `contains(range:)` and throw before reaching the rope).
- **Not addressed here:** DEF-011's read-performance regression (the RI walk adds work only when the window edge actually sits on an RI; fast path confirmed out of scope, deferred pending benchmarks).

Open questions resolved 2026-08-01; the resolutions are folded into this proposal and recorded in design.md ("Resolved open questions"), ADR-012, and DEFECTS.md ("Decisions (2026-08-01 grilling)").
