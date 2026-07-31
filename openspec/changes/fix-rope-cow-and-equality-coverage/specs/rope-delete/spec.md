## MODIFIED Requirements

### Requirement: COW path-copying on delete

When a `TextRope` value is copied (via Swift's value semantics) and one copy is mutated via `delete`, the mutation SHALL NOT affect the other copy. The implementation MUST use copy-on-write path-copying: only nodes along the mutation path from root to the affected leaves are copied. Shared subtrees not on the mutation path MUST remain shared (reference-identical).

When the rope has a single owner, the delete descent MUST NOT hold a strong reference to a child node across the `ensureUniqueChild(at:)` call for that child's index. Reading a child's metrics for the descent decision (for example `children[i].summary.utf16`) MUST NOT bind the child node itself to a local that outlives the uniqueness check, because such an alias makes `isKnownUniquelyReferenced` observe a shared node and forces an unnecessary path copy on every delete. With no such alias present, a single-owner delete that leaves every affected node within its size bounds SHALL leave the entire root-to-leaf path reference-identical.

Deletes that push a leaf below `Node.minChunkUTF8` or an inner node below `Node.minChildren` trigger merging or redistribution, which constructs replacement nodes by design. The reference-identity guarantee above SHALL NOT be read as forbidding those allocations.

#### Scenario: Single-owner mutation avoids copying

- **WHEN** a `TextRope` has a single owner (no copies exist), the tree has more than one level, and `delete` removes a range that lies wholly inside one leaf and leaves every affected node within its size bounds
- **THEN** the root, every inner node on the path from the root to that leaf, and the leaf itself SHALL each remain reference-identical (`===`) to the node held at the same position before the delete
- **AND** the rope's `content` SHALL equal the original content with the deleted range removed

#### Scenario: Single-owner delete leaves off-path siblings identical

- **WHEN** a single-owner multi-level rope is deleted as above
- **THEN** every node not on the root-to-leaf mutation path SHALL also remain reference-identical, so that no part of the tree is reallocated

#### Scenario: Single-owner in-place guarantee is pinned by test

- **WHEN** the delete descent is changed so that a child node is bound to a local that is still live when `ensureUniqueChild(at:)` runs for that index
- **THEN** at least one named test SHALL fail — the guarantee MUST NOT be verifiable only by inspecting the root or a node that lies off the delete path

#### Scenario: Rebalancing delete may allocate replacement nodes

- **WHEN** a single-owner delete reduces a leaf below `Node.minChunkUTF8` or an inner node below `Node.minChildren`, so that merging or redistribution runs
- **THEN** the operation MAY replace the affected leaves or inner nodes with newly constructed nodes, and the resulting tree SHALL still satisfy the content, summary, and structural invariants for delete
