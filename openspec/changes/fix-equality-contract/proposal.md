## Why

`TextRope.==` is not one relation. `Sources/TextRope/TextRope.swift:50-54` runs a code-unit-flavored summary early-out (`utf8`/`utf16`/`lines`) and then falls through to `lhs.content == rhs.content` — Swift `String ==`, which decides by **Unicode canonical equivalence**. The result is a hybrid nobody can state, verified both ways (DEF-018, 2026-08-06):

- `TextRope("é") != TextRope("e\u{301}")` — canonically equal, rejected by the summary tier.
- `TextRope("e\u{301}\u{323}") == TextRope("e\u{323}\u{301}")` — byte-different (a CCC reorder: U+0323 has `ccc` 220, U+0301 has `ccc` 230), but the summaries match on all three fields and `String ==` calls the contents equal.

The canonical fallback breaks equality's most load-bearing property for an **offset-addressed** API: congruence. Two `==` ropes can report different `utf16Count` and diverge under the identical operation at the identical offset, which poisons exactly the consumers that exist — `RopeBuffer.==`, `SendableRopeBuffer.comparator(.content)`, echo suppression, and convergence checks. It is already a **cross-buffer drift today**: `MutableStringBuffer.==` goes through `NSString.isEqual` (`Sources/TextBuffer/Buffer/MutableStringBuffer.swift:147-152`), which is code-unit, so on the CCC pair the two `Buffer` conformers give opposite answers — the buffer types are supposed to be interchangeable.

The canonical spec is internally inconsistent about which relation it means: `openspec/specs/rope-core-types/spec.md:106` mandates equality of the `content` **strings** (canonical), while `:114`'s tier-2 soundness proof — every `Summary` field is a pure additive function of the text, so differing summaries prove differing content — is only valid under **code-unit** semantics. Under canonical semantics the proof is false: `"é"` and `"e\u{301}"` would be "equal" while differing in `utf8` and `utf16`, making the early-out unsound. Today the implementation is protected only by the accident that its two tiers disagree in the safe direction.

The same canonical dialect leaks into two more places:

- **Operation-log types** (`BufferOperation`, `UndoGroup`, `OperationLog`) use *synthesized* `Equatable` over `String` members, so `comparator(.content, .undoHistory)` mixes dialects inside a single call.
- **The drift oracle** compares `content` with `XCTAssertEqual` on `String` — `RopeBufferDriftTests.assertDriftMatch` (`:19`) and `assertUndoEquivalence` / `assertSendableUndoEquivalence` (`Sources/TextBufferTesting/AssertUndoEquivalence.swift:62,116`). A rope-side normalization divergence would pass the whole oracle suite undetected, even though the oracle it compares against is byte-exact internally. (`RopeTransferIntegrationTests` already asserts `Array(...utf8)` at `:400,405,419,467`; the drift and undo-equivalence helpers never got the same treatment.)

Underlying gap: the repo has **no normalization policy** — the word appears in no source, spec, or doc. Ruling (2026-08-06, codex consult plus a unanimous four-juror Opus tribunal across app-developer, API-design, Unicode-pipeline, and maintenance lenses; full argument in DEFECTS.md "Decisions (2026-08-06 grilling)"): **code-unit (UTF-8) equality package-wide**, normalization stated as a caller-boundary policy, and the two questions the canonical dialect was silently answering given their own named APIs.

## What Changes

- **`TextRope.==` tier 3 becomes code-unit.** `lhs.content.utf8.elementsEqual(rhs.content.utf8)` replaces `lhs.content == rhs.content`. Tier 1 (root identity) and tier 2 (summary early-out) are unchanged — the tier-2 soundness proof becomes genuinely valid instead of accidentally safe. The materializing form stays for now; the allocation-free leaf-streaming zipper remains the deferred perf slice on the DEF-010 ledger, now unblocked by this ruling but **not implemented here**.
- **DocC on the conformance states the dialect**: code-unit equality, deliberately different from Swift `String ==`, with the `é` / `e` + U+0301 example inline.
- **Two new predicates on `TextRope`** (TextRope target, stdlib-only, no Foundation — ADR-013 holds):
  - `isCanonicallyEquivalent(to:) -> Bool` — Swift `String ==` semantics over the two contents. DocC routes callers: use it for render-equality questions; `==` answers byte fidelity.
  - `isTriviallyIdentical(to:) -> Bool` — tier 1 exposed, O(1) (`root === root`), under the SE-0494 spelling and contract: `true` implies `==`, `false` implies nothing. Defined on our own type, so no toolchain or availability dependency.
- **One dialect in the op log.** `BufferOperation.Kind` gets an explicit `==` comparing its `String` payloads with `utf8.elementsEqual`; ranges and offsets compare as before. `UndoGroup` and `OperationLog` keep their synthesized conformances and inherit the dialect through it — `actionName` stays a Swift `String` comparison, being a menu label rather than document content. The explicit `==` forfeits the synthesized conformance's automatic field coverage; that risk is pinned with a comment at the implementation and a spec clause.
- **The drift oracle hardens to byte-exact.** `assertDriftMatch` and both `assertUndoEquivalence` overloads (plus `assertSendableUndoEquivalence`) add a UTF-8 comparison of `content` alongside the existing `String` assertion — the `String` assert stays for readable failure output, the byte assert decides fidelity.
- **The spec is repaired and given a normalization policy.** The equality requirement is restated in code-unit terms (tier list retained, proof now valid) and grows the two predicates and a future-`Hashable` constraint. A new requirement states that `TextRope` never normalizes, and routes callers: render-equality → the canonical predicate; uniform storage → Foundation normalization at ingress, with the CJK-compatibility-ideograph caveat named; range derivation → the existing composed-sequence / word / line expansion APIs.
- **Regression tests**, red-first where honest: the CCC-reorder pair (unequal under the new `==`, equal summaries asserted) **fails on current `main`** — that is the behavior change; the NFC/NFD pair is green today via the early-out and lands as a pin; both are canonically equivalent under the new predicate; `isTriviallyIdentical` is pinned `true` for copies sharing a root and `false` after copy-on-write divergence with equal content.
- **`Hashable` is deliberately not added.** The spec records the constraint any future conformance must satisfy (hash exactly the code units `==` compares).

## Capabilities

### New Capabilities
<!-- None — this change repairs and extends existing capabilities. -->

### Modified Capabilities
- `rope-core-types`: the `Equatable` requirement is repaired to code-unit UTF-8 equality (tier list retained, tier-2 proof now sound), gains the `isCanonicallyEquivalent(to:)` and `isTriviallyIdentical(to:)` contracts and the future-`Hashable` constraint, and gains NFC/NFD and CCC-reorder unequal scenarios; a new requirement states the never-normalize storage guarantee and the caller-boundary normalization policy
- `rope-buffer-drift`: drift content assertions between the rope buffers and the `MutableStringBuffer` oracle must be byte-exact, so a normalization divergence cannot pass the suite
- `operation-log-types`: `BufferOperation.Kind` equality is code-unit over its content payloads, so content and undo-history comparisons speak one dialect

## Impact

- **Modified source:** `Sources/TextRope/TextRope.swift` (tier 3, conformance DocC, two new predicates), `Sources/TextBuffer/OperationLog/BufferOperation.swift` (explicit `Kind.==` plus the field-coverage comment), `Sources/TextBufferTesting/AssertUndoEquivalence.swift` (byte-exact content assertions in both overloads)
- **Modified tests:** `Tests/TextRopeTests/TextRopeEqualityTests.swift` (the two verified pairs, the two predicates), `Tests/TextBufferTests/RopeBufferDriftTests.swift` (`assertDriftMatch` byte assertion), `Tests/TextBufferTests/OperationLogTests.swift` (op-log dialect)
- **New test file:** `Tests/TextRopeTests/TextRopeNormalizationTests.swift` — the never-normalize storage guarantee across construction, insert, delete, and replace
- **Unchanged, deliberately:** `MutableStringBuffer.==` (already code-unit via `NSString.isEqual` — the target the rope side is being aligned *to*); `RopeBuffer.==` and `SendableRopeBuffer.comparator` (they delegate, and inherit the corrected dialect); `Summary`, `Node`, and every mutation path (this change touches no storage or tree code)
- **Defects closed:** DEF-018 (Medium)
- **Behavior change, disclosed in the CHANGELOG:** ropes (and therefore `RopeBuffer`, `SendableRopeBuffer`, and the op log) whose contents are canonically equivalent but code-unit different **with matching UTF-8, UTF-16, and line counts** now compare **unequal** where they previously compared equal. The affected inputs are combining-mark sequences differing only in canonical order; NFC-vs-NFD pairs already compared unequal via the summary early-out. This aligns `RopeBuffer` with `MutableStringBuffer`, which has always answered unequal on those inputs.
- **Not addressed here:** the allocation-free leaf-streaming equality zipper (DEF-010 ledger — this change unblocks it by fixing the semantics it would have to preserve, and deliberately leaves the materializing form in place); `Hashable`; any normalizing API (there is none, by policy); `rope-transfer-convergence`, whose byte-identical requirement is already stated in the spec (`:43`) and already asserted byte-exactly in `RopeTransferIntegrationTests` — no delta needed, verified rather than assumed
