---
status: accepted
date: 2026-03-11
title: "ADR-007: No parent pointers in rope nodes"
---

# ADR-007: No parent pointers in rope nodes

## Context

Tree data structures sometimes include parent pointers for convenient upward traversal (e.g., finding a node's sibling without descending from the root). For a rope, parent pointers would simplify rebalancing after split/merge — you could walk up from the affected leaf instead of returning status up the call stack.

Sub-agent review identified a fatal interaction between parent pointers and copy-on-write semantics.

## Decision

No parent pointers. All upward traversal uses path-from-root — mutation functions return rebalancing status up the call stack, and the caller handles it at each level.

## Alternatives considered

**Weak parent pointers (`weak var parent: Node?`).** The standard approach for reference-type trees. However, `isKnownUniquelyReferenced` returns `false` for any object that has *any* weak reference — even if there's only one strong reference. This is documented Swift runtime behavior. With weak parent pointers, `isKnownUniquelyReferenced` would always report the node as shared, causing every mutation to copy every node regardless of actual sharing. COW becomes "copy always."

**Unowned parent pointers (`unowned var parent: Node`).** Same problem — unowned references also prevent the uniqueness check from succeeding. Additionally, unowned references crash on access after deallocation, which is dangerous during tree restructuring.

**Parent pointer + separate uniqueness tracking.** Maintain a manual reference count or version flag instead of relying on `isKnownUniquelyReferenced`. Adds complexity and defeats the purpose of using Swift's built-in COW primitive.

## Consequences

- **COW works correctly.** `isKnownUniquelyReferenced` accurately reports whether a node is shared, enabling copy-on-write with zero unnecessary copies.
- **Mutation functions are recursive, returning status.** Insert returns "I split, here's the new sibling." Delete returns "I'm undersized, merge me." The parent handles the response at each level. This is standard B-tree implementation style.
- **Sequential access needs a cursor.** Without parent pointers, moving to the "next leaf" from a given leaf requires descending from the root. A cursor type (stack of `(node, childIndex)` per level) amortizes this to O(1) per step. Not needed for v1 but the rope's API should accommodate it later.
