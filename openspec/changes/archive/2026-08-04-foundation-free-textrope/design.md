## Context

ADR-013 resolves DEF-006a by moving code instead of amending the spec: TextRope's stated identity is a zero-dependency stdlib-only target, so its NSRange surface migrates out rather than the `rope-target-setup` MUST-NOT clause gaining a carve-out. The Foundation footprint in `Sources/TextRope/` today, verified by survey:

| File | Foundation usage |
|---|---|
| `TextRope+Navigation.swift` | `import Foundation`; `public func content(in utf16Range: NSRange) -> String` |
| `TextRope+Delete.swift` | `import Foundation`; `public mutating func delete(in utf16Range: NSRange)` |
| `TextRope+Replace.swift` | `import Foundation`; `public mutating func replace(range utf16Range: NSRange, with string: String)` |
| `TextRope+ComposedSequences.swift` | `import Foundation`; `public func composedCharacterSequences(in: NSRange)`, `public func composedCharacterSequence(at: Int)`; internal `expandingWindow` bridges to `NSString` and calls `rangeOfComposedCharacterSequence(s)` |
| `TextRope.swift`, `Documentation.docc/Documentation.md` | doc comments/examples naming `NSRange` (no code dependency) |

`insert(_:at: Int)` and everything else (`Node`, `Summary`, split/merge, construction) are already Foundation-free. Consumers inside the package: `RopeBuffer` and `SendableRopeBuffer` call `rope.content(in:)`, `rope.delete(in:)`, `rope.replace(range:with:)`, `rope.insert(_:at:)`, `rope.composedCharacterSequences(in:)`, `rope.composedCharacterSequence(at:)` — all from the TextBuffer target, where `Buffer.Range == NSRange`. `SendableRopeBuffer`'s undo/redo paths (`SendableRopeBuffer.swift:173-199`) construct NSRanges for rope calls as well.

This change lands last in the 0.10.0 train (DEFECTS.md decision, 2026-08-01), after the five defect-fix changes, so the migration diff is purely mechanical against the then-current source — including code those changes add inside `TextRope+ComposedSequences.swift` (the regional-indicator anchor walk from `fix-composed-sequence-reads`).

## Goals / Non-Goals

**Goals:**
- `Sources/TextRope/` contains zero `import Foundation`, zero `NSRange`, zero `NSString` — the `rope-target-setup` clause becomes literally true (DEF-006a)
- Consumers importing TextBuffer compile unchanged: signature-identical NSRange methods exist as TextBuffer-target extensions on `TextRope`, forwarding at zero overhead
- `RopeBuffer` / `SendableRopeBuffer` observable behavior is bit-for-bit unchanged, proven by the untouched drift and conformance suites
- `TextRopeTests` exercises the `Range<Int>` primitives directly
- `rope-replace` degenerate-case requirements describe observable behavior (DEF-006b)

**Non-Goals:**
- No `#if canImport(Foundation)` gate anywhere (ADR-013: nothing left in TextRope to gate; gating the TextBuffer extensions would guard a configuration that cannot exist)
- No deprecation cycle for the removed TextRope NSRange methods (ADR-013: no direct consumer exists)
- No cross-platform/Linux CI for the now-portable TextRope target — portability is a consequence, not a shipped promise; verification stays grep- and build-based on macOS
- No performance work; no behavior change to any read or mutation
- No new Swift-native grapheme-segmentation API on TextRope (see D4 — it would have different semantics than the NSString-parity API and zero consumers)

## Decisions

### D1: API mapping — what moves where

| Current (TextRope, NSRange) | New primitive (TextRope, stdlib-only) | Convenience wrapper (TextBuffer target) |
|---|---|---|
| `content(in: NSRange) -> String` | `content(in: Range<Int>) -> String` | `content(in: NSRange)` — `@inlinable @inline(__always)` forwarder |
| `delete(in: NSRange)` | `delete(in: Range<Int>)` | `delete(in: NSRange)` — forwarder |
| `replace(range: NSRange, with: String)` | `replace(range: Range<Int>, with: String)` | `replace(range: NSRange, with:)` — forwarder |
| `insert(_: String, at: Int)` | unchanged (already conforming) | — (no NSRange form exists today; none is added) |
| — | `utf16CodeUnits(in: Range<Int>) -> [UTF16.CodeUnit]` (new, `package`-scoped, supports D5) | — |
| `composedCharacterSequences(in: NSRange) -> String` | — (no rope-level primitive; see D4) | full implementation relocates here, signature unchanged |
| `composedCharacterSequence(at: Int) -> String` | — (see D4) | full implementation relocates here, signature unchanged |
| internal `findLeaf(utf16Offset:)`, `LeafPosition` | unchanged, stays internal | not exposed; the relocated window machinery uses public primitives only (D5) |

Wrapper home: one new file `Sources/TextBuffer/TextRope+NSRange.swift`. Relocated composed machinery: `Sources/TextBuffer/TextRope+ComposedSequences.swift` (same filename, new target — the git move keeps history legible).

### D2: `Range<Int>` stays a range of UTF-16 code units

Nothing about the offset unit changes. `NSRange` at this boundary was always a pair of UTF-16 code-unit offsets; `Range<Int>` is the same pair expressed half-open (`location ..< location + length`). All arithmetic, preconditions, summaries, and scenarios translate mechanically: `NSRange(location: 5, length: 6)` ⇢ `5..<11`. Spec scenarios restate with that literal translation so expected values are untouched.

Precondition semantics tighten slightly for free: a `Range<Int>` cannot represent a negative length (`5..<3` traps in the stdlib at construction), so the primitives keep only `lowerBound >= 0` and `upperBound <= utf16Count` checks. `NSNotFound` and negative locations/lengths remain representable in `NSRange`; the TextBuffer wrappers own those checks (`location != NSNotFound`, `location >= 0`, `length >= 0` — same trap behavior the TextRope methods have today, including the DEF-004-decided trap-before-empty-return ordering for reads) before constructing the half-open range and forwarding.

### D3: Zero-overhead wrappers — `@inlinable @inline(__always)`

The wrappers exist so that TheArchive2-class consumers (import TextBuffer, use NSRange everywhere) compile and behave identically. `@inlinable` exports the forwarding bodies into the module interface so cross-module callers inline them; `@inline(__always)` removes the residual call in debug-ish configurations. The bodies are pure argument re-typing plus the D2 preconditions — no logic — so inlining collapses each wrapper to the primitive call. This package ships as source via SPM (no ABI-stability concern), making `@inlinable` cost-free. The attributes are implementation detail and deliberately do **not** appear in spec deltas; the specs state signature availability and behavioral parity only.

### D4: Composed-sequence APIs are the documented exception — they live entirely in the TextBuffer layer

ADR-013 says the composed-sequence APIs "likewise" become `Range<Int>`-based, and also that TextRope ends up with "no Foundation reference". Both cannot hold: the composed APIs' contract — entrenched at rope and buffer level by `fix-composed-sequence-reads`, and load-bearing for `MutableStringBuffer` drift parity — is *equality with full-document `NSString.rangeOfComposedCharacterSequence(s)`*. That contract is not implementable with stdlib segmentation. Measured on the current toolchain (2026-08-01, comparing `NSString.rangeOfComposedCharacterSequence(at:)` against Swift `Character` boundaries at every offset):

| Input | NSString composed sequences | Swift grapheme clusters |
|---|---|---|
| `"a\r\nb"` | `\r` and `\n` are **two** sequences | `\r\n` is **one** `Character` |
| `"\u{0600}1"` (prepend, Arabic number sign) | **two** sequences | **one** `Character` (UAX #29 GB9b) |
| ASCII, combining marks, Zalgo stacks, surrogate pairs, ZWJ families, skin tones, keycaps, Hangul jamo, Indic conjuncts, kana voicing, variation selectors, RI runs (even and odd) | identical | identical |

A Swift-native reimplementation inside TextRope would therefore observably change `RopeBuffer.unsafeCharacter(at:)` over CRLF (returning `"\r\n"` where `MutableStringBuffer` returns `"\r"`) and break the drift suite. Reimplementing CFString's cluster rules by hand (Swift graphemes *minus* CRLF-joining *minus* GB9b) would chase a private, OS-versioned oracle — rejected as unmaintainable.

Decision: the composed-sequence APIs move **wholly** into the TextBuffer extension layer, keeping their NSRange signatures and NSString semantics. They are not "wrappers" over a rope primitive — they are the full `expandingWindow` machinery (including the RI-run parity anchor and window cap from `fix-composed-sequence-reads`), relocated to where Foundation legitimately lives. TextRope gains no Swift-grapheme twin: it would carry subtly different semantics under a near-identical name, and no consumer exists for it (`RopeBuffer`/`SendableRopeBuffer` need the NSString semantics). This deviates from one clause of ADR-013 and is flagged as proposal Open Question 1; the deviation preserves the ADR's two governing constraints (Foundation-free TextRope; unchanged TextBuffer-consumer surface) at the cost of the one it contradicts.

### D5: Foundation-free support surface for the relocated window machinery

The relocated `expandingWindow` needs three things from the rope that used to come from inside the target:

1. **Window materialization** — already served by the public `content(in: Range<Int>)`; window edges are adjusted onto scalar boundaries before materializing, exactly as today.
2. **Trail-surrogate detection at window edges** — today a private helper walking a leaf chunk via internal `findLeaf`.
3. **Regional-indicator run-start walk** (added by `fix-composed-sequence-reads`) — today walks leaf chunks directly, avoiding per-code-unit descents (that change's design D2 risk note).

(2) and (3) need raw code-unit access at arbitrary offsets — including offsets that split a surrogate pair, which `content(in:)` must not be asked to do (it produces `String`s and assumes scalar-aligned edges). TextRope therefore gains one new stdlib-only primitive, `package`-scoped rather than public — its only consumer is the same-package TextBuffer target, so it stays off the library's semver surface entirely:

```swift
package func utf16CodeUnits(in utf16Range: Range<Int>) -> [UTF16.CodeUnit]
```

O(log n + k), valid for **any** in-bounds range regardless of scalar or character boundaries, defined as the corresponding slice of `content`'s UTF-16 encoding. The relocated machinery derives trail-surrogate checks (read 1 unit) and the RI-run walk (read backward in fixed-size blocks, e.g. 128 units, so the walk costs O(runLength + blocks·log n) instead of one descent per code unit) from it. This keeps `findLeaf` and `LeafPosition` internal — no `@_spi`, no widening of the structural surface. The drift suites and the composed-sequence test file (which moves along with the API) are the oracle that the re-plumbed leaf access is faithful.

### D6: Test strategy — primitives tested where they live, parity tested at the seam

- **`TextRopeTests` rewrites in place to `Range<Int>`** (~92 NSRange usages: `TextRopeNavigationTests` 10, `TextRopeNavigationPreconditionTests` 1, `TextRopeDeleteTests` 36, `TextRopeReplaceTests` 20, `TextRopeStressTests` 25) and drops its `import Foundation` lines. This is the ADR's "a feature": the rope test target exercises the real primitives and proves the target is consumable without Foundation.
- **Migration safety net:** the `Range<Int>` primitives are introduced *first*, with the TextRope NSRange methods temporarily forwarding to them. At that point the entire existing NSRange-based suite runs through the new primitives — equivalence by construction, before a single test is rewritten.
- **`TextRopeComposedSequencesTests` moves to `Tests/TextBufferTests/`** with its API (its subject now lives in the TextBuffer target). Its assertions are unchanged.
- **New `Tests/TextBufferTests/TextRopeNSRangeParityTests.swift`** pins the wrapper seam: for representative ropes, each NSRange wrapper result equals the `Range<Int>` primitive result (content, mutation outcomes, counts), plus trap tests for `NSNotFound` and negative location/length. Thin by design — behavior depth stays in the rope suite; this file only proves the forwarding and the NSRange-specific validation.
- **Drift/conformance suites (`RopeBufferDriftTests`, buffer conformance, transfer, undo) are deliberately untouched** — they are the proof that buffer-observable behavior did not move.

### D7: Spec homes

- The NSRange convenience surface is specced in `rope-target-setup` as a new requirement under the TextBuffer-target relationship (that capability already owns "TextBuffer depends on and re-exports TextRope"). It is a cross-target layering fact, not `RopeBuffer` behavior, so `rope-buffer-conformance` — which describes the `Buffer` conformer — is the wrong home.
- The composed-sequence read requirements stay in `rope-utf16-navigation` (capability = composed reads over rope storage), with the API-providing target restated. Moving them to a buffer capability would orphan their rope-shape-independence scenarios.
- Deltas are authored against the post-train canonical state, since this change archives last (proposal, Sequencing). Task 1.1 re-verifies requirement headers and wording against the actually-archived specs — in particular `rope-utf16-navigation`'s composed requirements (added by `fix-composed-sequence-reads`) and `rope-delete`'s "Undersized leaf merging after delete" (modified by `fix-rope-split-point`; deliberately not touched here).

## Risks / Trade-offs

- **[Risk] Same-signature coexistence during migration** — while TextRope still declares `content(in: NSRange)` and the TextBuffer extension layer also declared it, calls inside TextBuffer would be ambiguous or silently shadowed. Mitigation: strict task ordering — the TextBuffer wrappers are added in the *same slice* that removes the TextRope NSRange methods (tasks 5.x); no intermediate state declares both.
- **[Risk] The NSString oracle moves under the relocated code** — composed-sequence semantics remain pinned to Foundation behavior, which is OS-versioned. Unchanged from today; the drift tests compare against `MutableStringBuffer` so both sides move together, and the D4 divergence table documents why the oracle cannot be replaced by the stdlib.
- **[Risk] Re-plumbed leaf access in the RI-run walk regresses performance or fidelity** — the walk loses direct chunk access and goes through `utf16CodeUnits(in:)` block reads. Fidelity is guarded by the moved composed tests and RI drift sweeps; cost is bounded by the existing 4096-unit cap and block-amortized descents, on a path that only runs when a window edge lands inside an RI run. Not benchmarked here (DEF-011 owns read performance).
- **[Risk] An unknown external TextRope-product consumer uses the NSRange API** — the break is deliberate and un-gated (ADR-013). Mitigation is disclosure: a CHANGELOG breaking-change entry with the one-line fix (import TextBuffer, or translate `NSRange` ⇢ `Range<Int>` at the call site).
- **[Trade-off] ADR-013's "composed-sequence APIs likewise" clause is not honored literally** (D4) — accepted to preserve NSString parity and the Foundation-free clause simultaneously; confirmed 2026-08-03 and recorded as ADR-013's "Amendment 2026-08-03" section (proposal Resolved Question 1).
- **[Trade-off] `utf16CodeUnits(in:)` adds a cross-target seam** to support one consumer — contained by `package` visibility (tools-version 6.2): invisible outside the package, zero semver surface, freely changeable when the window machinery evolves. The rejected alternatives (`public`, `@_spi`, or exposing `findLeaf`) each commit to more: public API for one caller, or tree structure instead of content.
- **[Risk] Rebase drift** — five changes archive before this one; requirement wording this change modifies may shift. Mitigation: task 1.1 is a hard gate that re-diffs every delta against canonical before implementation starts.
