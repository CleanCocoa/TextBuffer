---
status: accepted
date: 2026-03-11
title: "ADR-006: Always-rooted rope — empty leaf instead of optional root"
---

# ADR-006: Always-rooted rope — empty leaf instead of optional root

## Context

An empty `TextRope` needs a representation. The obvious choice is `root: Node?` where `nil` means empty. The alternative is an always-present root — an empty leaf node for an empty document.

## Decision

Always-rooted: `TextRope` holds a non-optional `root: Node`. An empty rope has an empty leaf node. The root is never nil.

## Alternatives considered

**Optional root (`root: Node?`).** Nil for empty documents. Every recursive function must handle the nil case at the top: `guard let root else { return ... }`. Every property accessor: `root?.summary.utf16 ?? 0`. This nil-check noise propagates through the entire codebase — insert, delete, content, navigation, COW checks. An empty document is a valid state that occurs constantly (new files, cleared buffers), so the nil path is exercised frequently.

## Consequences

- **Eliminates nil checks everywhere.** Every function can assume `root` exists. No optional unwrapping, no early returns for empty state, no `?? 0` defaults.
- **One trivial allocation for empty state.** An empty leaf node is a small fixed-cost object. For a library that manages text buffers, one extra allocation per empty document is negligible.
- **Simpler COW.** `isKnownUniquelyReferenced(&root)` works directly — no need for the `T?` overload or special-casing nil before the check.
- **`isEmpty` is `root.summary.utf8 == 0`** — a simple property check, not a nil check.
