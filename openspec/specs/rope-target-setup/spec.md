# rope-target-setup Specification

## Purpose
Positions the rope as an independently consumable building block: `TextRope` is a standalone SPM library target and declared product with zero external dependencies, so external packages can depend on the rope implementation without pulling in TextBuffer or AppKit, while the `TextBuffer` target depends on it and re-exports it (`@_exported import TextRope`) so consumers importing TextBuffer get all public rope types with a single import.

## Requirements
### Requirement: TextRope is a standalone SPM library target
The package SHALL declare a `TextRope` library target with zero external dependencies. The target SHALL compile independently — it MUST NOT depend on TextBuffer, Foundation's NSRange, AppKit, or any other target in the package.

#### Scenario: TextRope target builds with no dependencies
- **WHEN** `swift build --target TextRope` is executed
- **THEN** the target compiles successfully with zero external dependency imports

#### Scenario: TextRopeTests target exists
- **WHEN** `swift test --filter TextRopeTests` is executed
- **THEN** the test target compiles and runs, depending only on `TextRope`

### Requirement: TextBuffer depends on and re-exports TextRope
The `TextBuffer` target SHALL declare a dependency on `TextRope`. TextBuffer SHALL re-export TextRope via `@_exported import TextRope` so that consumers importing TextBuffer automatically have access to all public TextRope types.

#### Scenario: TextBuffer consumer accesses TextRope types
- **WHEN** a module imports only `TextBuffer`
- **THEN** public types from `TextRope` (e.g., `TextRope`) are available without a separate import statement

### Requirement: TextRope is a declared library product
The package SHALL declare `TextRope` as a library product, allowing external packages to depend on the rope implementation independently of TextBuffer.

#### Scenario: External package depends on TextRope alone
- **WHEN** an external `Package.swift` declares a dependency on this package and depends on the `TextRope` product
- **THEN** it can import `TextRope` and use its public API without pulling in TextBuffer or AppKit

