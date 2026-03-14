---
status: accepted
date: 2026-03-11
title: "ADR-004: UTF-8 rope storage with cached UTF-16 counts"
---

# ADR-004: UTF-8 rope storage with cached UTF-16 counts

## Context

The rope needs an internal encoding. The existing `Buffer` protocol uses `NSRange` (UTF-16 code unit offsets) for all operations. However, the long-term roadmap includes `UTF8Range` and Foundation-free `TextBufferCore`. The encoding choice for the rope determines whether this future is easy or requires a rewrite.

Apple's swift-collections `BigString` was researched as a reference implementation. It stores UTF-8 internally and caches all encoding counts (utf8, utf16, unicodeScalar, character) per tree node, enabling O(log n) navigation by any encoding unit.

## Decision

Store UTF-8 internally via `String` (which is natively UTF-8 in Swift 5+). Each tree node's `Summary` caches `utf8`, `utf16`, and `lines` counts for its subtree. Navigation to a UTF-16 offset is O(log n) — walk the tree using `summary.utf16` at each level to find the correct child. At the leaf, translate the remaining UTF-16 offset to a `String.Index` via the chunk's `utf16` view (O(chunk_size), bounded constant).

## Alternatives considered

**UTF-16 internal storage.** Match NSRange natively — no translation needed at the `Buffer` boundary. Simpler today, but:
- Paints into a corner: adding UTF-8 indexing later requires either dual storage or a rewrite
- Nobody except `NSString` uses UTF-16; Swift `String`, Rust, Go, and modern text engines all use UTF-8
- Apple's own rope (BigString) chose UTF-8 despite needing NSString compatibility

**Generic over encoding.** Make the rope parameterized on encoding unit (UTF-8 or UTF-16). Adds complexity with no current consumer for the UTF-16 variant. Premature generalization.

## Consequences

- **No corner painted.** When `UTF8Range` support arrives, the rope is already native UTF-8 — just expose it through a different metric without storage conversion.
- **O(log n) NSRange translation.** Cached `utf16` counts per node enable efficient UTF-16 offset lookup without scanning leaf content during tree navigation.
- **UTF-16 offset within a leaf is O(chunk_size).** Once the correct leaf is found, translating the remaining UTF-16 offset to a byte position requires walking the chunk's UTF-16 view. With max chunk size ~2KB, this is a bounded constant — does not affect the O(log n) complexity claim.
- **UTF-16 count computation on chunk creation is O(chunk_size).** Computing `utf16` count from UTF-8 requires scanning for 4-byte sequences (U+10000+, which produce surrogate pairs). This happens once per chunk creation and is cached in the summary.
- **Line count included for free.** Counting `\n` bytes during chunk construction adds negligible cost and enables O(log n) line-to-offset lookup for future `LineIndex` integration.
