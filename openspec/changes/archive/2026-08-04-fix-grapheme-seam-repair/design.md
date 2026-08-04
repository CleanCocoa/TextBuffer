## Context

ADR-012 states the invariant this change restores: *chunk seams never fall inside a grapheme cluster*. The 0.10.0 implementation enforces it at every **split point** (all splitting goes through `Node.rebalancedChunks` / `Node.leadingChunkEnd`, which only yield `Character` boundaries) but at only one **adjacency**: the CRLF seam. Every seam-related site consults the byte-matching predicate `crlfSeam(between:)`:

| Site | File | Role | Gated on |
| --- | --- | --- | --- |
| Insert post-splice check | `TextRope+Insert.swift:48` | detects a seam between `children[i-1]` and the spliced child, calls `repairCRLFSeam` | nothing (runs on every descent with `i > 0`) — only the predicate is too narrow |
| `repairCRLFSeam` | `TextRope+Insert.swift:104-134` | recombines the two seam leaves via `Node.rebalancedChunks`, splices overflow siblings, prunes an emptied right leaf, recomputes both spines | invoked by the check above |
| Delete merge gate | `TextRope+Delete.swift:87` (`hasCRLFSeam`, `:95-103`) | decides whether `mergeUndersizedChildren` runs at all when nothing is undersized and no child was removed | the seam predicate |
| Leaf merge loop | `Node+Merge.swift:31` (`mergeUndersizedLeaves`) | combines `current` with the next leaf when a seam spans them, via `combinedLeaf` → `rebalancedChunks` | the seam predicate |
| Inner merge loop | `Node+Merge.swift:76` (`mergeUndersizedInnerNodes`) | same, one level up, via `combinedInner` | the seam predicate |

A seam-spanning cluster forms by **adjacency change**, not by a wrong split: insert puts a combining mark at leaf-local offset 0 (DEF-016 repro 1 — `a` | `\u{301}a…`), or delete removes the base character that separated a leaf's trailing `a` from the next leaf's leading `\u{301}` (repro 2). Neither leaf is undersized, so no size-driven machinery fires, and neither seam is CRLF, so no seam-driven machinery fires.

**Key insight (from DEFECTS.md's root-cause note): `\r\n` is one Swift `Character`.** The CRLF seam machinery is therefore already the grapheme-seam repair, specialized to a single two-byte cluster. The general fix is to generalize the *predicate* and leave the *machinery* — recombination through `rebalancedChunks`, overflow splicing, spine summary recomputation, merge-loop combination — exactly where it is.

The test-side validator already encodes the general invariant: `leafSeamViolations(in:)` (`Tests/TextRopeTests/TreeInvariantValidation.swift:111-126`) joins the leaves and asks whether each seam offset is a valid `String.Index` `Character` boundary of the whole content, unconditionally, with no starvation carve-out. The producer is what lags.

## Goals / Non-Goals

**Goals:**
- Restore the seam invariant after **every** mutation: insert, delete, and (by composition) replace
- One seam predicate, `graphemeSeam(between:)`, in agreement with the test-side `leafSeamViolations` validator — the same producer/validator pairing `Node.isBoundaryStarved` has for starvation
- Reuse the existing repair machinery; no new rebalancing mechanism
- Close the stress-coverage gap so the per-operation-validated seed (DEF-007, seed `0xDEF007`) can catch this defect class in the future

**Non-Goals:**
- No change to split-point selection (`Node+Split.swift` is correct; DEF-001 is fixed)
- No change to construction: `chunkLeaves` carves one string at `Character` boundaries and every seam it creates is between characters that were already adjacent — it cannot form an adjacency-change seam
- No change to `replace`: it composes `delete` + `insert` and inherits their repairs
- No NSString composed-sequence semantics (see boundary-semantics decision below)
- No performance work beyond keeping the predicate O(seam-adjacent cluster length)

## Decisions

### D1. `graphemeSeam(between:)` — the generalized predicate

Replace `crlfSeam(between:)` (`Node+Merge.swift:2-10`) with:

- Walk to the left subtree's rightmost leaf and take its last `Character` (`chunk.last`); walk to the right subtree's leftmost leaf and take its first `Character` (`chunk.first`) — the same two walks the CRLF predicate does today, reading a `Character` instead of a byte.
- The seam is a violation iff `String(l) + String(r)` contains **fewer than two** `Character`s — i.e. Swift stdlib grapheme breaking joins them into one cluster.

Properties:

- **Stdlib-only.** `Character` segmentation is Swift stdlib; the TextRope target stays Foundation-free (ADR-013).
- **CRLF falls out**: `"\r" + "\n"` is one `Character`, so the general rule subsumes the special case byte-for-byte. Lone `\r` next to lone-`\n`-followed-by-more is likewise handled identically (`"\r\n"` count 1).
- **Agreement with the validator.** For a tree whose *other* seams are valid, the local pair test agrees with `leafSeamViolations`' whole-content test. The one segmentation rule with non-local context is regional-indicator parity (flag emoji): a leaf's internal parse fixes the RI parity at its right edge, and because the leaf's own left seam is a true document boundary (induction over seams left-to-right), the last `Character` parsed leaf-locally is the last `Character` of the document prefix — so the pair test and the whole-content test classify the seam identically. The regression suite pins this with an RI case (complete flag | lone RI must NOT be flagged; lone RI | lone RI must be flagged and repaired).
- **Cost**: O(length of the two edge clusters) per checked adjacency, instead of O(1) byte peeks. Bounded by the longest cluster at the seam; see Risks.

### D2. Reuse `repairCRLFSeam` as `repairGraphemeSeam`

The insert-side repair (`TextRope+Insert.swift:104-134`) is already fully general: it concatenates the two seam leaves' chunks, runs `Node.rebalancedChunks` (which splits only at `Character` boundaries — so the repaired seam is legal by construction), writes chunk 0 and chunk 1 back, splices `chunks[2...]` as overflow siblings up the right spine with `splitInner` cascade, prunes the right leaf when the combination fits in one chunk, and recomputes both spines' summaries. Rename it `repairGraphemeSeam`; not one line of its body depends on the seam being CRLF.

**A repair may legally produce ADR-012's starved shapes.** `rebalancedChunks` on the combined content can return a minimal-shortfall two-way split (one leaf under `minChunkUTF8`, starvation-provable) or, for a pathological cluster, a whole-cluster leaf over `maxChunkUTF8`. That is correct: the seam invariant is absolute, the byte bounds soften under starvation (ADR-012), and the validator's `chunkSizeViolations` already accepts exactly these shapes. The specs state this so a future reader does not "fix" a starved repair output back into a seam violation.

Delete-side: `combinedLeaf` (`Node+Merge.swift:54-65`) already recombines through `rebalancedChunks` and spills extra chunks into the merge accumulator — untouched except for who invokes it.

### D3. Unconditional seam checks at every mutation-touched adjacency

The exact call sites, from reading `TextRope+Insert.swift`, `TextRope+Delete.swift`, `Node+Merge.swift`:

**Insert** — `TextRope+Insert.swift:48`, the post-splice check `if i > 0 && Self.crlfSeam(between: node.children[i - 1], and: node.children[i])`. Adjacency analysis for the insert descent: a splice at leaf-local offset > 0 changes no seam-edge character; a splice at leaf-local offset 0 changes the first `Character` of `children[i]`, touching exactly the `children[i-1] | children[i]` adjacency — which is the checked one. A splice cannot land at the *end* of a leaf that has a right neighbor: the descent (`remaining < childUTF16`) routes a boundary offset into the next child at local offset 0, so "insert at end" only reaches the document's last leaf, which has no right seam. Overflow siblings spliced at `i+1...` end where the original leaf ended, so the run's right edge character is unchanged and that pre-existing adjacency stays valid; interior seams of the carved run come from `chunkLeaves` and are legal by construction; `redistributeStarvedEdge` recombines through `rebalancedChunks`, likewise legal. **Conclusion: the one existing check site is the complete set for insert — it is already unconditional (never gated on sizes), and only its predicate changes.** This is why repro 1 is a one-predicate fix: at `i == 1` the check runs today and returns false only because `a\u{301}` is not CRLF.

**Delete** — two sites:
1. The merge gate `TextRope+Delete.swift:87`: `if childBecameUndersized || !indicesToRemove.isEmpty || hasCRLFSeam(node)`. `hasCRLFSeam` (`:95-103`) scans every adjacent child pair; it becomes `hasGraphemeSeam` over `graphemeSeam(between:)`. The or-term is what makes the delete-path check unconditional: repro 2 has nothing undersized and nothing removed, so without it the merge machinery is never entered. Deletion touches adjacencies by changing a leaf's first/last `Character` or by removing children — all become seams between children of the inner nodes on the deletion path, each of which runs this gate bottom-up.
2. The merge loops, `Node+Merge.swift:31` (`mergeUndersizedLeaves`) and `:76` (`mergeUndersizedInnerNodes`): the `crlfSeam(between: current, and: node.children[i])` disjunct becomes `graphemeSeam(...)`, so once the gate fires the loop actually combines the seam pair (via `combinedLeaf` / `combinedInner`) regardless of sizes. The fixed-point guard at `:38-42` (accept a starved shape without retrying) is unchanged and applies to seam-driven combinations exactly as to size-driven ones.

**Replace** — no site: composes delete + insert.

**Construction** — no site: `chunkLeaves` cannot create adjacency-change seams (Non-Goals).

### D4. Boundary semantics: Swift `Character`, not NSString composed sequences

The invariant is defined over Swift stdlib extended grapheme clusters (`Character`), per ADR-012 — the same segmentation `rebalancedChunks`, `isBoundaryStarved`, and `leafSeamViolations` already use, and the only one available in a Foundation-free target. NSString's `rangeOfComposedCharacterSequences` machinery draws some boundaries differently; that parity layer lives in TextBuffer (`TextRope+NSStringParity` surface) per ADR-013's 2026-08-03 amendment and is neither consulted nor affected here. A seam that NSString would consider mid-sequence but Swift considers a `Character` boundary is *legal* — the structural invariant serves leaf-local `Character` iteration and DEF-009's window precondition, both Swift-segmentation consumers.

### D5. Stress alphabet gains extenders; oracle comparison hardened where needed

Add to `stressCharset` (`TextRopeStressTests.swift:559-567`): `"\u{301}"` (combining acute — the DEF-016 operand), `"\u{200D}"` (ZWJ), `"\u{FE0F}"` (variation selector). Effects to account for:

- Random inserts can now place a lone extender at any offset, including leaf boundaries — the class the per-operation-validated seed (`0xDEF007`) never generated (its alphabet had no character that joins leftward).
- **Content-comparison implication**: Swift `String ==` compares canonical equivalence, so `"e" + "\u{301}"` equals `"é"`. Rope and oracle apply identical operations, so equality still holds; but a byte-transposition bug could now hide behind canonical equivalence. The stress assertions already compare `utf16Count`/`utf8Count` alongside content; the tasks add a code-unit-level comparison (`Array(content.utf8) == Array(oracle.utf8)`) in at least the dedicated per-op seed so fidelity stays byte-exact.
- The `singleCharacters` helper (`:455-459`) filters to `utf16.count <= 2` and excludes `"\r\n"`; lone extenders pass that filter, which is intended — single-char insert tests exercising extenders at position 0 and end are exactly the adjacency shapes wanted. `validUTF16Offset` needs no change: it guards surrogate halves, and each new operand is a single BMP scalar (one UTF-16 unit).
- Some existing stress helpers derive expectations positionally; any test whose expectation breaks from the alphabet change must be adjusted with the reason recorded (tasks require justifying every touched expectation).

## Risks / Trade-offs

- **More repairs fire → tree-shape churn.** Seam-driven combination now triggers on any joining pair, e.g. any lone-extender insert at a leaf head. Shapes only change where they were violations (or where a repair legally rebalances), and content/counts are unchanged by construction; the full suite runs before any expectation is touched, mirroring the fix-rope-split-point discipline. → Mitigation: red-first repros pin the two known shapes; per-op stress seed validates every operation after the alphabet change.
- **Predicate cost.** `graphemeSeam` reads two `Character`s instead of two bytes, on every insert descent adjacency and every delete-path child pair scan (`hasGraphemeSeam` is O(children) per touched inner node). Cluster length at real seams is single-digit bytes; the extra work is bounded and on mutation paths that already do O(chunk) splicing. → Mitigation: keep the predicate leaf-edge-local (no whole-content joins in the producer); note in DEF-011's ledger if profiles ever show it.
- **Segmentation locality (RI parity).** The pair-local predicate relies on every leaf's left seam being valid to agree with whole-content segmentation (D1). A latent seam violation elsewhere could in principle skew parity — but the invariant is restored by this change and validated per operation, so the precondition holds inductively. → Mitigation: RI cases in the regression tests pin both directions (flag|RI legal, RI|RI repaired).
- **Repair outputs starved shapes.** A repaired seam can legally emit an undersized (starvation-proven) or whole-cluster oversized leaf; a reader expecting `[min, max]` after "repair" may misread this as a new bug. → Mitigation: stated in the spec deltas and asserted in tests via `chunkSizeViolations` (empty) rather than byte-range pins.
- **Canonical-equivalence masking in the oracle** (D5). → Mitigation: code-unit comparison in the per-op seed.

## Alternatives Considered

- **Keep CRLF machinery, add a separate combining-mark check.** Another byte- or scalar-class predicate (e.g. "right leaf starts with a combining scalar") under-approximates grapheme breaking: misses ZWJ joins, variation selectors, Hangul jamo, RI parity — and drifts from the validator. The stdlib already ships the exact decision procedure; use it.
- **Normalize seams lazily at read time** (reassemble clusters spanning seams in the read paths). This is ADR-012's rejected byte-strict regime through the back door: it re-imposes permanent read-path complexity on every consumer to spare the mutation path one predicate, and it abandons the structural invariant DEF-009's hard precondition rests on. Rejected by ADR-012 already.
- **Full-content seam sweep after every mutation** (run `leafSeamViolations`-style validation over the joined content and repair whatever it finds). Correct but O(n) per mutation; the mutation-touched-adjacency analysis (D3) shows the touched set is exactly the sites already instrumented, so a sweep buys generality nobody needs at asymptotic cost. The validator keeps the whole-content form — where O(n) is fine — as the independent check.
- **Prevent instead of repair: forbid splices that land mid-cluster at leaf edges** (e.g. route an offset-0 extender insert into the previous leaf). Handles repro 1 but not repro 2 (delete exposes an adjacency without any splice), so repair machinery is needed anyway; prevention would then be a second mechanism to keep in agreement. One mechanism, repair, covers both.
- **Rebuild the seam subtree via `buildTree` instead of in-place repair.** Rejected for the same reason as in fix-rope-split-point (2026-08-01, open question 3): re-allocates the seam's whole subtree where the sibling-splice path already exists.
