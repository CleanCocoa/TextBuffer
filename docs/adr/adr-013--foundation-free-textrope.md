---
status: accepted
date: 2026-08-01
amended: 2026-08-03
title: "ADR-013: Foundation-free TextRope with Range<Int> primitives"
---

# ADR-013: Foundation-free TextRope with Range<Int> primitives

## Context

The canonical `rope-target-setup` spec requires that TextRope "MUST NOT depend on TextBuffer, Foundation's NSRange, AppKit, or any other target" — yet four TextRope source files `import Foundation` and take `NSRange` in public signatures, and three sibling canonical specs mandate exactly those signatures. The 0.9.0 archive promoted both sides of the contradiction (DEF-006 in DEFECTS.md). One side had to move.

Amending the spec to permit NSRange was considered: cheapest, but it enshrines a Foundation dependency in a target whose stated identity is zero dependencies.

## Decision

The code moves; the clause stands.

- TextRope's public range-taking API becomes **`Range<Int>`-based** (half-open, stdlib-only, UTF-16 offsets): `delete(in: Range<Int>)`, `replace(range: Range<Int>, with:)`, and `content(in: Range<Int>)`. `insert(_:at: Int)` is already conforming. ~~and the composed-sequence APIs likewise~~ The composed-sequence APIs do **not** migrate — see Amendment 2026-08-03.
- The existing NSRange-taking methods **move** — signature-identical — into `@inlinable @inline(__always)` extensions on `TextRope` in the **TextBuffer target**, which is Foundation-bound by construction (`Buffer.Range == NSRange`). Forwarding is zero-overhead.
- The NSRange methods are **removed outright from TextRope** in the same release (0.10.0). No deprecation cycle: consumers importing TextBuffer (which `@_exported`s TextRope) see identical signatures via the extensions, and no direct TextRope-with-NSRange consumer exists (verified against TheArchive2).
- **No `#if canImport(Foundation)` gate** anywhere: TextRope contains no Foundation reference to gate, and gating the TextBuffer extensions would guard a configuration that cannot exist. If a standalone cross-platform TextRope consumer materializes, a shim is a three-line addition then.
- `TextRopeTests` rewrites to the `Range<Int>` API — a feature: the test target exercises the real primitives.

## Amendment 2026-08-03: composed-sequence APIs stay in the TextBuffer layer

The original decision said the composed-sequence APIs would "likewise" become `Range<Int>`-based on TextRope. That was wrong, for an empirical reason found while authoring the `foundation-free-textrope` change:

**The finding.** The composed-sequence contract is *defined as* NSString parity (`rangeOfComposedCharacterSequence(s)`), and measurement shows that segmentation is not stdlib-reproducible: NSString treats CRLF as two sequences where Swift has one `Character`, and splits before prepend scalars (e.g. U+0600) where Swift joins. Regional-indicator runs, ZWJ chains, combining marks, Hangul, Indic conjuncts, and keycaps all match — the divergence is real but narrow. A `Range<Int>` implementation on Foundation-free TextRope would have to either break the parity contract that `fix-composed-sequence-reads` entrenches at rope and buffer level, or reimplement NSString's non-Unicode-conforming segmentation by hand. Both are worse than the deviation.

**The revised decision.** The composed APIs move *wholly* — the full `expandingWindow` machinery, not forwarders — into the TextBuffer target and stay NSRange-based. TextRope instead gains one `package`-scoped stdlib primitive, `utf16CodeUnits(in: Range<Int>) -> [UTF16.CodeUnit]`, so the relocated machinery keeps surrogate-safe block access without `findLeaf` leaving the target and without adding public API. No Swift-grapheme-semantics twin is added on TextRope: zero consumers would exist for one.

**What survives unchanged.** The Foundation-free clause becomes true exactly as decided; only the *location* of the composed implementation changes, and its observable contract does not move at all — which is the point.

**The cost, stated plainly.** TextRope alone can no longer answer "what composed sequence is at offset k." A future Foundation-free consumer of the standalone TextRope product gets code-unit and Swift `Character` access, but not NSString-parity clusters — those require importing TextBuffer. The original decision quietly implied this cost away; this amendment makes it explicit.

## Sequencing

The migration lands **last** in the 0.10.0 train, after the defect-fix changes (which were authored against the NSRange surface): fixes stop being open sooner, the five in-flight proposals stay valid, and the migration diff stays purely mechanical. The `rope-replace` white-box amendment (DEF-006b, observable-behavior wording) rides this change, which touches every rope capability spec's signatures anyway.

## Consequences

- The `rope-target-setup` MUST-NOT clause becomes literally true with no carve-out.
- All rope capability specs restate signatures in `Range<Int>` terms, with the NSRange convenience layer specced under TextBuffer's buffer capabilities.
- Callers inside this package (`RopeBuffer`, `SendableRopeBuffer`) switch to the Int primitives internally.
- Breaking only for a hypothetical external TextRope-only NSRange consumer; none known. TheArchive2 consumes the TextBuffer product exclusively.
- Composed-sequence requirements stay under `rope-utf16-navigation` but name the TextBuffer target as the providing target; the parity oracle remains Foundation — the deliberate, documented exception to "TextRope-only semantics live in TextRope."
