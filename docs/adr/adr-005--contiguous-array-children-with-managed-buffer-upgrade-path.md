---
status: accepted
date: 2026-03-11
title: "ADR-005: ContiguousArray children with ManagedBuffer upgrade path"
---

# ADR-005: ContiguousArray children with ManagedBuffer upgrade path

## Context

Rope inner nodes hold references to child nodes. The storage choice for children affects allocation count, cache behavior, and COW interaction. Sub-agent review identified a "double-COW" problem: the `[Node]` array is itself a COW type inside the COW node. Path-copying a mutation through depth D with branching factor B causes O(B × D) pointer copies — the entire children array at each level.

Apple's BigString uses `ManagedBuffer` to store children inline in the node allocation, collapsing two heap allocations into one per inner node.

## Decision

Use `ContiguousArray<Node>` for children in v1. Document `ManagedBuffer` as an upgrade path for when benchmarks justify the complexity.

## Alternatives considered

**`Array<Node>`.** Standard Swift Array. Adds Objective-C bridging overhead on Apple platforms. `ContiguousArray` skips this with no API difference.

**`ManagedBuffer<Header, Node>` inline storage.** Single heap allocation per inner node — children live in the same cache line as the header. Superior for path-copying (build replacement nodes with known child counts). However:
- Fixed size at allocation time; growing requires full reallocation
- More complex API (`withUnsafeMutablePointers`, manual capacity management)
- Apple's rope uses it because they have 15-child nodes and extreme performance requirements
- For branching factor 8, the double-COW cost is ~56 pointer copies per mutation at max depth — measured in nanoseconds

**Tuple-based fixed storage** (e.g., `(Node?, Node?, ..., Node?)`). Inline, no heap allocation for the children. But cumbersome to work with in Swift, no dynamic indexing without unsafe tricks.

## Consequences

- **Double-COW is real but bounded.** With max 8 children and tree depth ≤7, worst case is 56 pointer copies per mutation. Acceptable for a text editor workload.
- **Two heap allocations per inner node.** One for the `Node` object, one for the `ContiguousArray` buffer. For a 10K-leaf tree (~1400 inner nodes), that's ~2800 heap objects.
- **Simple implementation.** `ContiguousArray` has the same API as `Array`. No unsafe pointer management, no capacity planning.
- **Clear upgrade path.** If profiling shows the double-allocation or double-COW is a bottleneck, switch inner node storage to `ManagedBuffer<Header, Node>`. The node's public interface doesn't change — only the internal storage layout. This decision should be revisited when benchmarks exist.
