---
status: accepted
date: 2026-08-01
title: "ADR-013: Foundation-free TextRope with Range<Int> primitives"
---

# ADR-013: Foundation-free TextRope with Range<Int> primitives

## Context

The canonical `rope-target-setup` spec requires that TextRope "MUST NOT depend on TextBuffer, Foundation's NSRange, AppKit, or any other target" — yet four TextRope source files `import Foundation` and take `NSRange` in public signatures, and three sibling canonical specs mandate exactly those signatures. The 0.9.0 archive promoted both sides of the contradiction (DEF-006 in DEFECTS.md). One side had to move.

Amending the spec to permit NSRange was considered: cheapest, but it enshrines a Foundation dependency in a target whose stated identity is zero dependencies.

## Decision

The code moves; the clause stands.

- TextRope's public range-taking API becomes **`Range<Int>`-based** (half-open, stdlib-only, UTF-16 offsets): `delete(in: Range<Int>)`, `replace(range: Range<Int>, with:)`, `content(in: Range<Int>)`, and the composed-sequence APIs likewise. `insert(_:at: Int)` is already conforming.
- The existing NSRange-taking methods **move** — signature-identical — into `@inlinable @inline(__always)` extensions on `TextRope` in the **TextBuffer target**, which is Foundation-bound by construction (`Buffer.Range == NSRange`). Forwarding is zero-overhead.
- The NSRange methods are **removed outright from TextRope** in the same release (0.10.0). No deprecation cycle: consumers importing TextBuffer (which `@_exported`s TextRope) see identical signatures via the extensions, and no direct TextRope-with-NSRange consumer exists (verified against TheArchive2).
- **No `#if canImport(Foundation)` gate** anywhere: TextRope contains no Foundation reference to gate, and gating the TextBuffer extensions would guard a configuration that cannot exist. If a standalone cross-platform TextRope consumer materializes, a shim is a three-line addition then.
- `TextRopeTests` rewrites to the `Range<Int>` API — a feature: the test target exercises the real primitives.

## Sequencing

The migration lands **last** in the 0.10.0 train, after the defect-fix changes (which were authored against the NSRange surface): fixes stop being open sooner, the five in-flight proposals stay valid, and the migration diff stays purely mechanical. The `rope-replace` white-box amendment (DEF-006b, observable-behavior wording) rides this change, which touches every rope capability spec's signatures anyway.

## Consequences

- The `rope-target-setup` MUST-NOT clause becomes literally true with no carve-out.
- All rope capability specs restate signatures in `Range<Int>` terms, with the NSRange convenience layer specced under TextBuffer's buffer capabilities.
- Callers inside this package (`RopeBuffer`, `SendableRopeBuffer`) switch to the Int primitives internally.
- Breaking only for a hypothetical external TextRope-only NSRange consumer; none known. TheArchive2 consumes the TextBuffer product exclusively.
