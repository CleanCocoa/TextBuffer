## ADDED Requirements

### Requirement: Drift tests prove RopeBuffer insert selection equivalence with MutableStringBuffer
For every insert operation scenario, applying the same `insert(_:at:)` call to both a `RopeBuffer` and a `MutableStringBuffer` with identical initial state SHALL produce identical `content` and `selectedRange` afterwards.

#### Scenario: Insert before insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `insert("XX", at: 2)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert at insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `insert("XX", at: 5)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert after insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `insert("XX", at: 7)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert before selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 3}`
- **AND** `insert("XX", at: 2)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert at selection start
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 3)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert within selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 5)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert at selection end
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 7)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Insert after selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `insert("XX", at: 9)` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

### Requirement: Drift tests prove RopeBuffer delete selection equivalence with MutableStringBuffer
For every delete operation scenario, applying the same `delete(in:)` call to both a `RopeBuffer` and a `MutableStringBuffer` with identical initial state SHALL produce identical `content` and `selectedRange` afterwards.

#### Scenario: Delete before insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `delete(in: {1, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete after insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `delete(in: {7, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete across insertion point
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 0}`
- **AND** `delete(in: {3, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete within selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {2, 6}`
- **AND** `delete(in: {4, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete overlapping selection start
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {4, 3}`
- **AND** `delete(in: {2, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete overlapping selection end
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {4, 3}`
- **AND** `delete(in: {5, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete entire selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {3, 4}`
- **AND** `delete(in: {3, 4})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete encompassing selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {4, 2}`
- **AND** `delete(in: {2, 6})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete before selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {5, 3}`
- **AND** `delete(in: {1, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Delete after selection
- **WHEN** both buffers start with content `"0123456789"` and `selectedRange = {2, 3}`
- **AND** `delete(in: {7, 2})` is applied to both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

### Requirement: Drift tests prove RopeBuffer sequential operation equivalence with MutableStringBuffer
Applying a sequence of mixed insert, delete, and replace operations to both buffers SHALL produce identical `content` and `selectedRange` after every intermediate step, not just at the end.

#### Scenario: Sequential inserts with selection
- **WHEN** both buffers start with content `"abcdefghij"` and `selectedRange = {3, 4}`
- **AND** three sequential inserts are applied at offsets before, within, and after the selection
- **THEN** both buffers SHALL have identical `content` and `selectedRange` after each insert

#### Scenario: Mixed insert and delete operations
- **WHEN** both buffers start with identical content and selection
- **AND** a sequence of insert, delete, and insert operations is applied
- **THEN** both buffers SHALL have identical `content` and `selectedRange` after each operation

### Requirement: Drift tests prove RopeBuffer replace selection equivalence with MutableStringBuffer
For replace operations, applying the same `replace(range:with:)` call to both buffers SHALL produce identical `content` and `selectedRange` afterwards.

#### Scenario: Replace before selection
- **WHEN** both buffers start with identical content and `selectedRange` containing a selection
- **AND** `replace(range:with:)` is applied before the selection on both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Replace overlapping selection
- **WHEN** both buffers start with identical content and a selection range
- **AND** `replace(range:with:)` overlaps the selection on both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

#### Scenario: Replace after selection
- **WHEN** both buffers start with identical content and a selection range
- **AND** `replace(range:with:)` is applied after the selection on both
- **THEN** both buffers SHALL have identical `content` and `selectedRange`

### Requirement: Drift tests are cross-platform
The `RopeBufferDriftTests` SHALL NOT require `#if os(macOS)` gating because both `RopeBuffer` and `MutableStringBuffer` are cross-platform types. The tests MUST run on all platforms supported by Swift Package Manager.

#### Scenario: No platform gate
- **WHEN** the drift test file is compiled
- **THEN** it SHALL NOT contain `#if os(macOS)` or any platform-conditional compilation
- **AND** all tests SHALL execute on macOS and Linux
