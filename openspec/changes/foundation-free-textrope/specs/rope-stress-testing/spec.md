## MODIFIED Requirements

### Requirement: COW independence under mutation

The test suite MUST verify that when a `TextRope` is copied and one copy is mutated, the other copy is unaffected. This MUST be tested with insert, delete, and replace operations on the mutated copy.

#### Scenario: Insert on copy does not affect original
- **WHEN** `var a = TextRope(largeString)`, `var b = a`, then `b.insert("x", at: 0)`
- **THEN** `a.content` equals `largeString` and `b.content` equals `"x" + largeString`

#### Scenario: Delete on copy does not affect original
- **WHEN** `var a = TextRope(largeString)`, `var b = a`, then `b.delete(in: 0..<1)`
- **THEN** `a.content` equals `largeString` and `b.content` equals `largeString` with the first character removed

#### Scenario: Multiple mutations on copy preserve original
- **WHEN** a rope is copied and the copy undergoes 100 random mutations
- **THEN** the original rope's content remains unchanged throughout
