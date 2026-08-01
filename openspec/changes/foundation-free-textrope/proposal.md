## Why

The canonical `rope-target-setup` spec (`openspec/specs/rope-target-setup/spec.md:7`) requires that TextRope "MUST NOT depend on TextBuffer, Foundation's NSRange, AppKit, or any other target" — yet four TextRope source files (`TextRope+Navigation.swift`, `TextRope+Replace.swift`, `TextRope+Delete.swift`, `TextRope+ComposedSequences.swift`) `import Foundation`, take `NSRange` in public signatures, and bridge through `NSString` internally. Three sibling canonical specs (`rope-delete`, `rope-replace`, `rope-utf16-navigation`) mandate exactly those NSRange signatures. The 0.9.0 archive promoted both sides of the contradiction; this is DEF-006a. ADR-013 decides it: **the code moves; the clause stands.**

Riding along (DEF-006b): `rope-replace/spec.md:34,45` states "No insert operation SHALL occur" / "No delete operation SHALL occur" for the degenerate replace cases. That is false as written — `replace(range:with:)` composes `delete` + `insert` unconditionally; the degenerate cases are correct only because the primitives early-return. Since this change restates every `rope-replace` requirement in `Range<Int>` terms anyway, the white-box clauses are amended to describe shipped observable behavior in the same pass.

## What Changes

Per ADR-013 (`docs/adr/adr-013--foundation-free-textrope.md`):

- **`Range<Int>` primitives on TextRope.** `content(in:)`, `delete(in:)`, and `replace(range:with:)` become `Range<Int>`-based (half-open, stdlib-only, still UTF-16 code unit offsets — only the range *type* changes, never the unit). `insert(_:at: Int)` already conforms. A new stdlib-only primitive `utf16CodeUnits(in: Range<Int>)` is added so the relocated composed-sequence machinery keeps efficient, surrogate-safe code-unit access (see design.md D4/D5).
- **NSRange convenience layer in the TextBuffer target.** The existing NSRange-taking methods move — signature-identical — into `@inlinable @inline(__always)` extensions on `TextRope` inside the TextBuffer target, which is Foundation-bound by construction (`Buffer.Range == NSRange`). Forwarding is zero-overhead. Consumers importing TextBuffer (which `@_exported`s TextRope) see an unchanged API surface.
- **Composed-sequence APIs relocate wholly to the TextBuffer extension layer.** Their contract *is* `NSString.rangeOfComposedCharacterSequence(s)` parity, and NSString composed-sequence segmentation demonstrably diverges from Swift's stdlib grapheme clusters (CRLF and prepend characters — measured, see design.md D4). A Foundation contract keeps a Foundation home; TextRope gains no Swift-native grapheme twin. This is a documented deviation from ADR-013's "and the composed-sequence APIs likewise" clause, with the measurement as evidence (Open Question 1).
- **Outright removal, no deprecation cycle, no `canImport` gate.** The NSRange methods and all four `import Foundation` lines are removed from TextRope in the same release (0.10.0). No direct TextRope-with-NSRange consumer exists (verified against TheArchive2, which consumes the TextBuffer product exclusively).
- **`TextRopeTests` rewrites to the `Range<Int>` API** — a feature: the test target exercises the real primitives. The extension layer gets dedicated parity tests in `TextBufferTests`; the moved composed-sequence tests move with their API.
- **DEF-006b amendment.** The `rope-replace` degenerate-case requirements are restated as observable equivalences ("the result SHALL equal that of `delete(in:)` / `insert(_:at:)` alone") instead of asserting which internal operations do not run.
- **DEF-006a resolution.** `rope-target-setup`'s MUST-NOT clause becomes literally true with no carve-out, and is strengthened to a checkable form (no `import Foundation` anywhere under `Sources/TextRope/`).

## Capabilities

### New Capabilities
<!-- None — this change re-homes and re-types existing capabilities. -->

### Modified Capabilities
- `rope-target-setup`: the Foundation-free requirement becomes truthful and checkable (DEF-006a); a new requirement specs the NSRange convenience surface as a TextBuffer-target responsibility
- `rope-utf16-navigation`: `content(in:)` restated over `Range<Int>`; new `utf16CodeUnits(in:)` primitive; the composed-sequence read requirement re-homed to the TextBuffer extension layer (semantics unchanged)
- `rope-replace`: all requirements restated over `Range<Int>`; degenerate-case clauses amended to observable behavior (DEF-006b)
- `rope-delete`: signature and scenarios restated over `Range<Int>`
- `rope-edge-cases`: surrogate-boundary scenarios restated over `Range<Int>`
- `rope-stress-testing`: COW-independence scenario restated over `Range<Int>`

## Impact

- **Modified source (TextRope):** `TextRope+Navigation.swift`, `TextRope+Delete.swift`, `TextRope+Replace.swift` (re-typed, Foundation import dropped), `TextRope+ComposedSequences.swift` (deleted — relocated), `TextRope.swift` (doc comment), `Documentation.docc/Documentation.md` (NSRange examples)
- **New source (TextBuffer):** `TextRope+NSRange.swift` (forwarding wrappers), `TextRope+ComposedSequences.swift` (relocated expansion machinery, NSRange signatures kept)
- **Modified source (TextBuffer):** `RopeBuffer.swift`, `SendableRopeBuffer.swift` switch internal rope calls to the `Int`/`Range<Int>` primitives
- **Tests:** `TextRopeTests` NSRange usages rewritten (~92 usages across `TextRopeNavigationTests`, `TextRopeNavigationPreconditionTests`, `TextRopeDeleteTests`, `TextRopeReplaceTests`, `TextRopeStressTests`); `TextRopeComposedSequencesTests` moves to `TextBufferTests`; new `TextRopeNSRangeParityTests` in `TextBufferTests`
- **Breaking change (0.10.0):** breaking only for a hypothetical external TextRope-only NSRange consumer; none known. TextBuffer consumers see identical signatures via the extensions. CHANGELOG gets an explicit breaking-change entry.
- **Defects closed:** DEF-006a, DEF-006b. The remaining DEF-006 bullets belong to `fix-rope-split-point` (Node+Merge disclosure) and `docs-rope-disclosure` (Purpose-TBD headers); the rope-insert "splits into two" bullet is corrected by `fix-rope-split-point`'s n-way split delta.
- **Sequencing:** lands **last** in the 0.10.0 train, after `fix-rope-split-point` → `fix-composed-sequence-reads` → `fix-rope-cow-and-equality-coverage` → `perf-rope-equality-and-bulk-insert` → `docs-rope-disclosure` (DEFECTS.md decision, 2026-08-01). The defect fixes were authored against the NSRange surface; landing this last keeps those diffs valid and this diff purely mechanical. The spec deltas here are therefore authored against the **post-train canonical state** (notably: the composed-sequence requirements that `fix-composed-sequence-reads` adds to `rope-utf16-navigation`); tasks 1.x re-verify the deltas against the actually-archived wording before implementation starts.

## Open Questions

1. **ADR-013 deviation on composed sequences.** The ADR says the composed-sequence APIs "likewise" become `Range<Int>`-based on TextRope. Measurement shows NSString composed-sequence segmentation is not stdlib-reproducible (CRLF: NSString yields two sequences, Swift one `Character`; prepend scalars such as U+0600: NSString splits, Swift joins), so a Foundation-free TextRope implementation cannot honor the NSString-parity contract that `fix-composed-sequence-reads` just entrenched at both rope and buffer level. This proposal keeps the composed APIs NSRange-based in the TextBuffer extension layer and adds no Swift-native twin (zero consumers would exist for one). Confirm the deviation, or direct that TextRope additionally gain a Swift-grapheme-semantics `Range<Int>` API with its own, explicitly different, contract.
2. **Shape of the code-unit primitive.** `utf16CodeUnits(in: Range<Int>) -> [UTF16.CodeUnit]` is proposed as the single supporting primitive for the relocated window machinery (block reads amortize tree descents; safe on mid-surrogate ranges where `content(in:)` is not). Alternative: a scalar `utf16CodeUnit(at: Int)` accessor, simpler but O(log n) per unit during regional-indicator run walks. Confirm the block form.
