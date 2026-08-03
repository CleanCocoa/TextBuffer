## MODIFIED Requirements

### Requirement: Surrogate pairs at range edges

The test suite MUST verify correct behavior when delete or replace operations have range boundaries that fall at a surrogate pair boundary in UTF-16. Since TextRope uses UTF-16 offsets at the public API, ranges that start or end between the high and low surrogate of an emoji character MUST be handled without corrupting content.

#### Scenario: Delete starting at surrogate boundary
- **WHEN** a rope contains `"a🎉b"` (UTF-16 offsets: a=0, high=1, low=2, b=3) and `delete(in: 1..<3)` removes the full emoji
- **THEN** `content` is `"ab"` and summaries are correct

#### Scenario: Delete ending at surrogate boundary
- **WHEN** a rope contains `"a🎉b"` and `delete(in: 0..<1)` removes just `"a"`
- **THEN** `content` is `"🎉b"` and the emoji is intact

#### Scenario: Replace spanning surrogate pair
- **WHEN** a rope contains `"a🎉b"` and `replace(range: 1..<3, with: "XX")` replaces the emoji
- **THEN** `content` is `"aXXb"` and summaries are correct

#### Scenario: Delete range covering multiple emoji
- **WHEN** a rope contains `"🎉🚀💡"` (each emoji is 2 UTF-16 code units) and `delete(in: 2..<4)` removes the middle emoji
- **THEN** `content` is `"🎉💡"` and `utf16Count` is `4`

#### Scenario: Large rope with emoji at chunk boundaries
- **WHEN** a multi-chunk rope is constructed such that an emoji's surrogate pair spans near a chunk boundary, and a delete/replace targets that region
- **THEN** `content` equals the expected result and no surrogate pair is corrupted
