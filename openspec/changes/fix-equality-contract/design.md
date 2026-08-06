## Context

Equality in this package is currently three relations wearing one name:

| Site | File | Relation today |
| --- | --- | --- |
| `TextRope.==` tier 1 | `Sources/TextRope/TextRope.swift:51` | root identity (`===`) |
| `TextRope.==` tier 2 | `TextRope.swift:52` | summary equality — code-unit-flavored (`utf8`, `utf16`, `lines`) |
| `TextRope.==` tier 3 | `TextRope.swift:53` | `String ==` — **canonical equivalence** |
| `RopeBuffer.==` | `Sources/TextBuffer/Buffer/RopeBuffer.swift:146-151` | delegates to `TextRope.==` |
| `SendableRopeBuffer.comparator(.content)` | `SendableRopeBuffer.swift:250-251` | delegates to `TextRope.==` |
| `SendableRopeBuffer.comparator(.undoHistory)` | `SendableRopeBuffer.swift:254-255` | `OperationLog.==` → synthesized → `String ==` — **canonical** |
| `MutableStringBuffer.==` | `MutableStringBuffer.swift:147-152` | `NSString.isEqual` — **code-unit** |
| Drift oracle | `RopeBufferDriftTests.swift:19`, `AssertUndoEquivalence.swift:62,116` | `XCTAssertEqual` on `String` — **canonical** |
| Transfer oracle | `RopeTransferIntegrationTests.swift:400,405,419,467` | `Array(...utf8)` — **code-unit** (already correct) |
| Stress oracle | `TextRopeStressTests.swift:705` | `Array(...utf8)` — **code-unit** (already correct, per `rope-stress-testing/spec.md:36`) |

Two observations drive the whole change. First, the package already *has* a majority dialect — Foundation's oracle, the stress oracle, and the transfer oracle are all byte-exact, and `rope-stress-testing/spec.md:36` already reasons explicitly that "combining marks make Swift `String` equality (canonical equivalence) weaker than byte equality". The rope's own `==`, the op log, and the drift oracle are the stragglers. Second, the canonical fallback is not merely inconsistent, it is *unsound in context*: the tier-2 proof in `rope-core-types/spec.md:114` is a valid proof about code units and a false statement about canonical equivalence, and the spec asserts both.

The ruling (DEFECTS.md, "Decisions (2026-08-06 grilling)") is recorded; this change implements exactly it. The tribunal's argument order, strongest first, is reproduced here only as far as it constrains the design:

1. **Congruence.** Equality on an offset-addressed type must be a congruence for the operations: `a == b` must imply `a.insert(s, at: i) == b.insert(s, at: i)`. Canonical `==` admits pairs whose `utf16Count` differs, so the *same* offset means different things in the two values. Anything downstream that says "these are the same document, skip the sync" — echo suppression, convergence checks — is then wrong in a way that surfaces late and silently: dropped edits, blessed divergence.
2. **Precedent.** swift-collections gives `BigString.UTF16View` code-unit equality (`"Café".utf16 != "Cafe\u{301}".utf16`), and `TextRope`'s entire public surface *is* a UTF-16 view. Every surveyed editor rope (ropey, crop, xi, VS Code, CodeMirror) is code-unit or not `Equatable` at all.
3. **Structure.** No normalization-invariant summary field exists or could cheaply exist, so canonical `==` deletes the O(1) early-out outright and forecloses the streaming comparison on the DEF-010 ledger — normalization is not chunk-local (swift-foundation documents exactly this constraint in `AttributedString`).
4. **Reversibility.** Widening from code-unit to canonical later is a cheap, compatible loosening; narrowing away from canonical is a breaking change with silent-failure semantics in the interim.
5. The transfer-convergence spec already demands byte-identical content (`rope-transfer-convergence/spec.md:43`).

Rejected alternatives, for the record: **canonical equivalence** (the silent-late failure modes above) and the **documented hybrid** (status quo blessed) — the hybrid's contract is literally unstatable, and it breaks buffer interchangeability precisely at the consuming app's 16 KB rope threshold, where documents switch from `MutableStringBuffer` to `RopeBuffer` and the answer to `==` changes with them.

## Goals / Non-Goals

**Goals:**
- One dialect — code-unit UTF-8 — for every content comparison the package performs or asserts: `TextRope.==`, the op log, the drift oracle, the undo-equivalence helpers
- Restore congruence: `a == b` implies the two behave identically under every offset-addressed operation
- Make the tier-2 soundness proof true rather than accidentally safe, and repair the spec's self-contradiction
- Give the two questions the canonical dialect was silently answering their own named, deliberate-at-the-call-site APIs
- State a normalization policy where there was none, and route callers to the right tool for each of the three distinct questions
- Close the drift-oracle hole so a future normalization divergence fails a test instead of shipping

**Non-Goals:**
- **No allocation-free streaming comparison.** Tier 3 keeps materializing both contents. The leaf-pair zipper is the DEF-010 ledger item, deferred pending a TheArchive2 profile; this change unblocks it (a byte-wise relation is streamable; a canonical one is not) and deliberately does not do it, so that the semantic change and the performance change land as separately verifiable slices.
- **No `Hashable`.** The constraint on a future conformance is recorded in the spec; no conformance is added.
- **No change to `MutableStringBuffer.==`.** It is already code-unit and is the thing the rope side is being aligned *to*.
- **No normalizing API anywhere in the package.** Not `TextRope`, not the buffers. Normalization is the caller's boundary decision.
- **No change to storage, tree, or mutation code.** No `Summary` field, no `Node`, no insert/delete/replace path is touched.
- **No `rope-transfer-convergence` spec delta.** Its byte-identical wording is already correct and its tests already assert bytes — verified, not assumed.

## Decisions

### D1. Tier 3 compares UTF-8 code units; tiers 1 and 2 are untouched

```swift
public static func == (lhs: TextRope, rhs: TextRope) -> Bool {
    if lhs.root === rhs.root { return true }
    guard lhs.root.summary == rhs.root.summary else { return false }
    return lhs.content.utf8.elementsEqual(rhs.content.utf8)
}
```

One line changes. `elementsEqual` over `String.UTF8View` is the minimal expression of the contract and does not depend on `String`'s comparison machinery at all. `Array(lhs.content.utf8) == Array(rhs.content.utf8)` would be equivalent but adds two array allocations on top of the two `content` materializations this tier already pays; `elementsEqual` adds none.

The materialization itself stays (Non-Goals). Note that tier 2 already guarantees the two contents have the same UTF-8 length before tier 3 runs, so the length check inside `elementsEqual` can never be the discriminator here — it is redundant but free, and keeping it means the expression is correct in isolation if the tiers are ever reordered.

**Why the tier-2 proof only now becomes valid.** Each `Summary` field is a pure additive function of the text's code units, and a node's summary is the sum over its subtree, so `root.summary` equals that function applied to `content`. Equal code units ⇒ equal summaries; contrapositive: differing summaries ⇒ differing code units. That is a proof *about code units*. Under canonical tier-3 semantics the required implication is "canonically equal ⇒ equal summaries", which is false (`"é"` vs `"e\u{301}"` differ in `utf8` and `utf16`), and the early-out would return `false` for a pair the contract calls equal. The current code is safe only because its tiers disagree in the conservative direction on that particular input class.

### D2. `isCanonicallyEquivalent(to:)` — the render-equality question, made deliberate

```swift
public func isCanonicallyEquivalent(to other: TextRope) -> Bool {
    content == other.content
}
```

The rejected canonical semantics are not *useless* — they answer a real question ("would these two render the same?"). Making that a named method rather than the default `==` moves the choice to the call site, which is the whole point: a reader of `a == b` should not have to know which Unicode relation the author meant. `==` implies this predicate; the converse does not hold.

Stdlib-only: Swift `String ==` is canonical equivalence by definition of the stdlib's comparison, no Foundation involved, so ADR-013's Foundation-free TextRope target is preserved. Note the asymmetry this creates with `content` materialization cost — this predicate is O(n) with no early-out available, and that is inherent (see Risks).

### D3. `isTriviallyIdentical(to:)` — tier 1, exposed

```swift
public func isTriviallyIdentical(to other: TextRope) -> Bool {
    root === other.root
}
```

SE-0494's spelling and, more importantly, its contract: **`true` implies `==`; `false` implies nothing.** Two ropes with identical code units report `false` once copy-on-write has given them separate roots. Callers must treat it as a fast *affirmative* — "definitely unchanged, skip the work" — and never as a negative.

Defining it on `TextRope` rather than reaching for a stdlib facility keeps it free of any toolchain or availability condition, and lets it mean exactly root identity rather than whatever a stdlib type's storage identity happens to mean.

The motivating use is app-side dirty tracking: no surveyed editor uses content equality for that (version counters are the norm), and this gives the consuming app the O(1) primitive to move in that direction. That note belongs to the release announcement, not to this repo.

### D4. Op-log dialect: explicit `==` on `Kind` only

`BufferOperation.Kind` gets the explicit comparison; `BufferOperation`, `UndoGroup`, and `OperationLog` keep synthesized conformances and inherit the dialect through the chain (`OperationLog` → `[UndoGroup]` → `[BufferOperation]` → `Kind`). This is the smallest cut that makes `comparator(.content, .undoHistory)` speak one dialect end to end.

`UndoGroup.actionName` stays a Swift `String` comparison, and that is a decision, not an oversight: it is a menu label, not document content. The dialect requirement is about text the buffer stores and replays; a canonically equivalent action name naming the same command is the same command.

**The cost of going explicit, pinned rather than hoped:** a synthesized `Equatable` automatically covers every field; a hand-written one silently ignores fields added later. A new associated value on `Kind` — or a fourth case — that nobody adds to the comparison produces an `==` that reports unequal values equal, the worst failure direction for an undo log. This is carried in three places: a comment at the implementation, a clause in the `operation-log-types` requirement text, and a scenario stating that extending `Kind` obliges extending `==` in the same change.

### D5. Oracle hardening supplements, never replaces

The byte assertion is *added* next to the `String` assertion; the `String` one is not removed. Rationale: `XCTAssertEqual` on two `String`s prints readable text on failure, while a `[UInt8]` mismatch prints two byte arrays. The pair gives a fast-readable diagnosis plus a fidelity gate, and the pair also localizes the diagnosis — String-equal but byte-unequal is *specifically* a normalization or canonical-order divergence, which is exactly the class this change exists to catch.

Sites: `RopeBufferDriftTests.assertDriftMatch`, both `assertUndoEquivalence` overloads, and (by delegation) `assertSendableUndoEquivalence`. `RopeTransferIntegrationTests` and `TextRopeStressTests` already assert bytes and are left alone.

### D6. Normalization policy: one requirement, three routes

The policy lives in **its own requirement** in `rope-core-types` rather than folded into the equality requirement. The equality requirement is about how `==` decides, in tiers; the normalization policy is about what *every* operation does to the bytes — construction, insert, delete, replace, materialization — and is therefore a storage-fidelity contract that happens to have equality as one consequence. Folding it in would have buried a document-wide guarantee inside an already-long comparison algorithm and forced a future reader looking for "does this thing normalize?" to read the `Equatable` requirement to find out. Keeping the equality requirement's scope tight also keeps the archiver's full-text reproduction obligation manageable on the requirement most likely to be amended again.

The routing exists because "canonical equivalence" was silently answering three different questions, and each has a different right answer:

| Question | Right tool | Wrong tool |
| --- | --- | --- |
| "Would these two render the same?" | `isCanonicallyEquivalent(to:)` | normalizing the storage |
| "All my documents should be NFC" | normalize at ingress, in the app (Foundation's `precomposedStringWithCanonicalMapping`) | expecting the rope to do it |
| "What is the whole character at this offset?" | the composed-sequence / word / line expansion APIs | normalization as a range primitive |

The ingress route carries a caveat the spec names explicitly: **NFC is not encoding-only.** It singleton-decomposes the CJK compatibility ideographs (U+F900–U+FAFF: `U+F900` → `U+8C48`), so blanket ingress normalization changes *characters*, not merely their representation, and a document round-tripped through it is not the document the user handed over. Recommending ingress normalization without that caveat would be recommending silent data loss to exactly the CJK-document users most likely to hit it.

### D7. `Hashable` recorded as a constraint, not added

Byte hashing is compositional over leaves — a future streaming implementation can hash leaf by leaf. Canonical hashing is not, for the same reason canonical comparison is not streamable. So the constraint is cheap to state and expensive to discover later: any future `Hashable` MUST feed exactly the UTF-8 code units `==` compares, no normalization and no shape-derived term. Stating it now costs a paragraph; discovering it after a conformance ships costs a breaking change.

## Risks / Trade-offs

- **This is a real behavior change, not a clarification.** Ropes whose contents are canonically equivalent, code-unit different, *and* summary-identical flip from equal to unequal — concretely, combining-mark runs differing only in canonical order. NFC-vs-NFD pairs are unaffected (already unequal via the early-out). Mitigation: disclosed in the CHANGELOG `Changed` section with the exact input class named, and the direction of the change is toward `MutableStringBuffer`, which has always answered unequal there — this *removes* a cross-buffer drift rather than introducing one.
- **A consumer relying on canonical `==` gets a false "changed" signal.** An app comparing a freshly loaded document against an in-memory one where the two came through different normalization paths will now see them as different and may re-sync or mark dirty. Mitigation: `isCanonicallyEquivalent(to:)` lands in the same change and is the one-line migration; the CHANGELOG `Added` entry points at it.
- **`isCanonicallyEquivalent(to:)` is O(n) with no early-out and no streaming form.** That is inherent to canonical equivalence, not an implementation shortfall, and it is a second reason not to have it as `==`. It should be documented as the expensive predicate so nobody reaches for it per keystroke.
- **The explicit `Kind.==` can rot** (D4). Pinned by comment, requirement clause, and scenario; still the change's main maintenance liability.
- **Byte assertions produce worse failure output than string assertions.** Mitigated by keeping both (D5).
- **`isTriviallyIdentical(to:)` invites misreading as "not equal".** Mitigated by DocC stating the one-directional contract explicitly and by a test pinning the `false`-with-equal-content case, which is the shape a misreading would break on.
- **The CCC-reorder regression test is red on current `main` by design.** That is the honest red-first signal for the behavior change and must not be "fixed" by weakening the assertion; the NFC/NFD test is green today and is a pin, labeled as such so nobody mistakes it for evidence the change works.

## Migration Plan

No API is removed and no signature changes; the two predicates are additive. A consumer that wants the previous tier-3 semantics writes `a.isCanonicallyEquivalent(to: b)`. A consumer that wanted byte fidelity all along — which is what the offset-addressed API implies — needs no change and gets a correct answer where it previously got a hybrid one.

## Open Questions

None. The ruling is recorded in DEFECTS.md with the tribunal's reasoning; the deferred items (streaming zipper, `Hashable`) are ledgered explicitly rather than left open.
