---
title: Product Requirements Document: Single Editor, Multiple Transferable Buffers
date: 2026-03-11
status: Draft
---

# Product Requirements Document: Single Editor, Multiple Transferable Buffers

**Audience:** TextBuffer maintainers, application developers embedding TextBuffer, implementers of transfer and undo infrastructure

---

## 1. Summary

TextBuffer currently provides two useful editing surfaces:

- `NSTextViewBuffer` for interactive, on-screen editing in AppKit applications, and
- `MutableStringBuffer` for lightweight, in-memory editing.

Applications commonly need **one persistent editor view** while managing **many logical documents or text states** in memory. Today, switching which text state is shown in the editor is awkward: content can be copied, but the full editor state — especially undo/redo behavior — does not transfer cleanly.

This product introduces a way to treat a visible editor and in-memory buffers as **equivalent representations of the same editing model**, so applications can:

- keep one `NSTextView` alive,
- switch which buffer it represents,
- move state between on-screen and off-screen representations,
- preserve content, selection, and undo/redo semantics, and
- keep transferred copies independent after the transfer.

The immediate solution is an **operation-log-based transferable undo model**. A later storage milestone may replace the internal history representation with a structurally shared rope while preserving the same product behavior.

---

## 2. Problem Statement

Many text-editing applications do not want to destroy and recreate their text view every time the user switches documents, tabs, notes, editors, or views. They want a single editor widget to remain on screen while the logical document behind it changes.

The missing capability is:

> **How can one text editor become another buffer's state without losing editing continuity?**

That state is not just the string. It includes:

- text content,
- insertion point or selected range,
- undo history,
- redo history,
- user-facing editing behavior.

A naive content copy is insufficient:

- it loses undo/redo history,
- it risks making document switching itself look like an undoable edit,
- it may couple histories between documents incorrectly,
- and it does not provide confidence that an off-screen copy behaves the same as the on-screen editor.

Applications need a principled buffer transfer model.

---

## 3. Product Vision

TextBuffer should let applications treat visible and in-memory buffers as **different affordances over the same editing behavior**.

From the application's point of view:

- the editor is the **interactive representation**, optimized for user input and display,
- the in-memory buffer is the **stored representation**, optimized for cheap retention and background management,
- and state can move between them without semantic loss.

In other words:

- **transfer-out** turns the editor's current state into an off-screen buffer, and
- **transfer-in** makes the editor represent a previously off-screen buffer.

After transfer, both sides should be independent copies with the same externally observable editing semantics.

---

## 4. Target Users

### Primary users

**Application developers using TextBuffer** to build:
- document-based Mac apps,
- note-taking applications,
- editors with tabs or sidebars,
- source editors with many open files,
- tools that keep a single editing surface while switching underlying text models.

### Secondary users

**TextBuffer maintainers and contributors** who need a clear statement of product behavior before implementing storage and undo architecture.

---

## 5. User Stories

### Story 1 — Tab switching without rebuilding the editor
As an app developer, I want to keep one `NSTextView` alive while switching between many logical text buffers, so that my UI remains stable and I do not need to constantly recreate editor views.

### Story 2 — Save current editor state off-screen
As an app developer, I want to capture the current editor state into an in-memory buffer, so that I can store many open documents efficiently while only displaying one at a time.

### Story 3 — Restore a previously off-screen document
As an app developer, I want to load an in-memory buffer into the editor, so that the user can continue editing it in the same visible text view.

### Story 4 — Preserve undo semantics across transfer
As an app developer, I want undo/redo behavior to be preserved when state moves between editor and memory, so that off-screen buffers behave like faithful editor copies rather than lossy snapshots.

### Story 5 — Keep histories independent after transfer
As an app developer, I want the editor and its transferred copy to diverge independently after transfer, so that undoing in one does not mutate or corrupt the other.

### Story 6 — Trust behavioral equivalence
As a TextBuffer maintainer, I want strong tests proving that on-screen and in-memory representations behave the same under edits, undo, redo, and selection restoration, so that transfer can be relied on as a true representation change rather than a best-effort copy.

---

## 6. Product Goals

### Goal 1 — One persistent editor, many logical documents
Applications can keep a single visible editor while switching among many in-memory buffers.

### Goal 2 — State transfer, not just content copy
Transfers preserve the complete editing state relevant to user experience:
- content,
- selection,
- undo/redo history,
- action grouping semantics.

### Goal 3 — Behavioral equivalence
A transferred in-memory buffer should behave the same as the editor-backed version for all externally observable buffer behavior covered by TextBuffer's contract.

### Goal 4 — Independence after transfer
After transfer, each representation owns its own future evolution. Histories are copied, not shared live.

### Goal 5 — Compatibility with AppKit editing workflows
The interactive editor should continue to support expected AppKit behavior such as Cmd+Z and Edit menu integration.

### Goal 6 — Evolution path toward advanced storage
The product should support a later storage upgrade (for example, rope-backed persistent storage) without changing the core user-facing transfer model.

---

## 7. Non-Goals

This product does **not** aim to solve all editor problems at once.

Out of scope for this PRD:

- attributed text or rich text fidelity,
- collaborative editing,
- conflict resolution between concurrent editors,
- persistence of undo history across app launches,
- tree-structured or branching undo history,
- replacing AppKit text editing wholesale,
- background sync protocols,
- multi-cursor editing,
- syntax highlighting architecture,
- file I/O and document loading policies,
- solving every future storage backend before shipping transfer.

---

## 8. Core Concepts

### 8.1 Interactive editor
The **interactive editor** is the on-screen text editing surface, currently represented by `NSTextViewBuffer`. It is optimized for user interaction and platform integration.

### 8.2 In-memory buffer
The **in-memory buffer** is the off-screen representation, currently `MutableStringBuffer`. It is optimized for storage efficiency and background retention.

### 8.3 Transfer-out
**Transfer-out** captures the editor's current state into a new in-memory buffer.

Expected outcome:
- the new in-memory buffer has equivalent content, selection, and undo history,
- the copy is independent from the editor after creation.

### 8.4 Transfer-in
**Transfer-in** loads a previously captured in-memory buffer into the interactive editor.

Expected outcome:
- the editor now represents that buffer's state,
- the editor behaves as if that state had always belonged to it,
- document switching itself is not recorded as an undoable user edit.

### 8.5 Behavioral equivalence
Two buffers are behaviorally equivalent if, from the surface:
- they report the same content,
- they report the same insertion point or selection,
- the same undo/redo sequence produces the same observable states,
- and grouped edits restore the same state.

---

## 9. Functional Requirements

### FR-1: Transfer-out must produce an in-memory copy
The system must provide an operation that creates an off-screen buffer from the current editor state.

### FR-2: Transfer-in must load a prior off-screen state into the editor
The system must provide an operation that makes the editor represent an in-memory buffer's state.

### FR-3: Content must transfer exactly
Transferred buffers must preserve text content exactly.

### FR-4: Selection state must transfer exactly
Transferred buffers must preserve insertion point or selected range exactly.

### FR-5: Undo/redo history must transfer as a copied history
Transferred buffers must preserve undo/redo behavior by copying history into the new representation.

### FR-6: Transfer must not create a user-visible undo step for document switching
Undoing after a document switch must undo edits in the represented buffer, not the act of switching represented buffers.

### FR-7: Histories must be independent after transfer
After transfer, new edits, undo, and redo in one representation must not mutate the other representation.

### FR-8: On-screen and in-memory buffers must be equivalence-testable
The product must support tests proving that the editor-backed and in-memory-backed implementations behave identically for edits and undo/redo.

### FR-9: Grouped edits must remain grouped after transfer
Undo grouping semantics must survive transfer so that user-perceived undo granularity remains stable.

### FR-10: AppKit editing integration must remain available
The visible editor must remain usable with standard AppKit undo interactions.

---

## 10. Experience Requirements

Although TextBuffer is a library, the product has user-facing behavioral expectations because applications expose its behavior directly.

### ER-1: Stable visual editor
Applications should be able to leave the visible editor intact while changing represented content.

### ER-2: No surprising undo behavior
Users should never experience undo as “switching documents back” or mutating a different logical document than the one they are editing.

### ER-3: No semantic downgrade when moving off-screen
A buffer moved off-screen should remain a fully capable editable state, not just a plain string cache.

### ER-4: Predictable return to a prior document
When a document is loaded back into the editor, it should feel like the same editing session resumed.

---

## 11. Constraints and Design Principles

### Constraint 1 — Current implementation reality
The existing `Undoable<Base>` built on `NSUndoManager` cannot be used directly for transferable histories because registered undo actions are bound to specific object instances.

### Constraint 2 — AppKit side effects exist
Replacing visible text in `NSTextView` will always trigger layout and Text Kit processing. This is normal system behavior and not the primary product problem.

### Constraint 3 — Behavior matters more than implementation identity
Applications care that editor and memory buffers behave the same, not that they share the same concrete implementation.

### Principle 1 — Preserve the `Buffer` abstraction
The solution should fit the existing `Buffer`-centered mental model rather than introducing product-level concepts foreign to TextBuffer.

### Principle 2 — Prefer explicit representation changes
Document switching is a representation change, not a text edit.

### Principle 3 — Keep future storage evolution possible
The first solution may use an operation log; a later solution may use structurally shared storage. The product behavior must survive that implementation change.

---

## 12. Success Criteria

The product is successful when all of the following are true:

1. A developer can keep one `NSTextView` alive while switching among many logical buffers.
2. A developer can create an in-memory copy of the editor that preserves content, selection, and undo/redo behavior.
3. A developer can load an in-memory buffer into the editor and continue editing it with equivalent behavior.
4. Undoing in the editor and undoing in a transferred memory copy produce the same observable states when starting from the same copied state.
5. After transfer, the two copies evolve independently.
6. Document switching is not itself exposed as an undoable text mutation.
7. The transfer model remains valid even if the storage backend later changes from mutable string storage to rope-backed storage.

---

## 13. Acceptance Scenarios

### Scenario A — Editor to memory transfer
Given an editor with text and undo history,  
when the application transfers it out to memory,  
then the resulting in-memory buffer has equivalent content, selection, and undo/redo behavior.

### Scenario B — Memory to editor transfer
Given an in-memory buffer with text and undo history,  
when the application transfers it into the editor,  
then the editor behaves equivalently to that buffer and can continue undo/redo independently.

### Scenario C — Independence after copy
Given an editor and a transferred in-memory copy,  
when new edits occur in one of them,  
then the other remains unchanged.

### Scenario D — Round-trip transfer
Given an in-memory buffer,  
when it is transferred into the editor and then transferred back out again,  
then all representations remain behaviorally equivalent for undo/redo from the copied state.

### Scenario E — No document-switch undo bug
Given the user switched the represented document in the editor,  
when they press Undo,  
then the system undoes the last edit within the represented document rather than undoing the act of switching representations.

---

## 14. Risks

### Risk 1 — Undo model mismatch
If the transfer-capable undo implementation diverges behaviorally from the current `Undoable`, applications may see subtle selection or grouping bugs.

**Mitigation:** treat existing `Undoable` as the behavioral reference and maintain equivalence tests.

### Risk 2 — AppKit integration surprises
Bridging library-managed undo behavior back into AppKit may expose edge cases around responder-chain behavior.

**Mitigation:** explicitly test Cmd+Z, redo, menu enablement, and action names.

### Risk 3 — Over-optimizing too early
Jumping directly to a rope or persistent structure before shipping the transfer behavior could slow delivery and increase complexity.

**Mitigation:** ship operation-log transfer first; evolve storage later behind the same behavior.

### Risk 4 — Treating transfer as a low-level copy only
If implementation focuses only on strings and ignores selection and undo semantics, the product will fail its core use case.

**Mitigation:** define transfer as complete editing-state transfer, not content replacement.

---

## 15. Release Strategy

### Phase 1 — Transferable behavior on current storage
Deliver transfer semantics and copied undo history using the existing mutable string-based buffers.

### Phase 2 — Advanced storage convergence
Introduce rope-backed storage later while preserving the same transfer behavior and public mental model.

This sequencing allows immediate user value while keeping a clear path to higher-performance storage.

---

## 16. Open Questions

1. What public naming best expresses transfer-in semantics: `represent`, `inherit`, `become`, or another term?
2. Should selection-only moves ever appear as standalone undoable events, or only as metadata attached to edit groups?
3. How much AppKit undo-manager compatibility should be exposed publicly versus hidden behind setup helpers?
4. When rope-backed storage arrives, should transfer continue to be described in product language exactly as it is now, even if internally it becomes version-pointer copying?

---

## 17. Relationship to Other Documents

- **`SPEC.md`** is the implementation-oriented solution specification for how this product behavior may be delivered.
- **`2026-03-07_spec-textbuffer-custom-storage.md`** explores broader editor-engine evolution and future storage directions.

This PRD is the top-level product statement: it defines the problem, the intended user-visible behavior, and the success criteria independent of implementation details.
