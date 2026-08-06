## MODIFIED Requirements

### Requirement: BufferOperation value type
`BufferOperation` SHALL be a public struct conforming to `Sendable` and `Equatable`. It SHALL contain a single stored property `kind` of type `BufferOperation.Kind`.

`BufferOperation.Kind` SHALL be a public enum conforming to `Sendable` and `Equatable` with exactly three cases:
- `insert(content: String, at: Int)` — text was inserted at a UTF-16 offset
- `delete(range: NSRange, deletedContent: String)` — text was deleted from a range
- `replace(range: NSRange, oldContent: String, newContent: String)` — text in a range was replaced

`Kind`'s `Equatable` conformance SHALL be **code-unit**: the recorded text payloads (`content`, `deletedContent`, `oldContent`, `newContent`) SHALL be compared as UTF-8 code unit sequences, not by Swift `String ==` (Unicode canonical equivalence). `NSRange` and `Int` payloads compare as before. This matches `TextRope`'s equality dialect, so that a single comparison spanning a buffer's content and its undo history — `SendableRopeBuffer.comparator(.content, .undoHistory)` — cannot answer one component in code units and the other canonically. `BufferOperation`, `UndoGroup`, and `OperationLog` MAY keep synthesized conformances and inherit the dialect through this one; `UndoGroup.actionName` is a user-facing menu label rather than recorded document text and is therefore outside this rule.

Because an explicit `==` forfeits the synthesized conformance's automatic coverage of every field, any case added to `Kind` — or any associated value added to an existing case — MUST be added to the comparison in the same change, and the implementation MUST carry a comment stating that obligation. A payload omitted from the comparison would make distinct operations compare equal, the worst failure direction for an undo log.

#### Scenario: BufferOperation is Equatable
- **WHEN** two `BufferOperation` values are created with identical `kind` values
- **THEN** they SHALL compare as equal via `==`

#### Scenario: BufferOperation is a value type
- **WHEN** a `BufferOperation` is assigned to a new variable and the original is mutated
- **THEN** the copy SHALL remain unchanged

#### Scenario: Different operation kinds are not equal
- **WHEN** an `insert` operation and a `delete` operation are compared
- **THEN** they SHALL compare as not equal

#### Scenario: Canonically equivalent text payloads are not equal
- **WHEN** `.insert(content: "é", at: 0)` (U+00E9) is compared with `.insert(content: "e\u{301}", at: 0)` (U+0065 U+0301), and when `.replace(range:oldContent:newContent:)` values differing only in the canonical order of combining marks are compared
- **THEN** each pair SHALL compare as not equal, even though Swift `String ==` reports the payload strings equal

#### Scenario: Every payload of every case participates in the comparison
- **WHEN** two `Kind` values of the same case differ in exactly one payload — the offset, the range, or any one text payload — with all others identical
- **THEN** they SHALL compare as not equal, for each payload of each case in turn

#### Scenario: Content and undo-history comparison speak one dialect
- **WHEN** `SendableRopeBuffer.comparator(.content, .undoHistory)` compares two buffers whose contents and whose recorded operations are canonically equivalent but code-unit different
- **THEN** the comparator SHALL report the buffers unequal, and each component SHALL individually report unequal — neither component SHALL answer canonically while the other answers in code units
