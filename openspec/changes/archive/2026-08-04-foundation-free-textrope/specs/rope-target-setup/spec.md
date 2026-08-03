## MODIFIED Requirements

### Requirement: TextRope is a standalone SPM library target

The package SHALL declare a `TextRope` library target with zero external dependencies. The target SHALL compile independently — it MUST NOT depend on TextBuffer, AppKit, or any other target in the package, and it MUST NOT import Foundation. No source file under `Sources/TextRope/` SHALL contain an `import Foundation` statement, reference `NSRange` or `NSString`, or use any other Foundation type. All public TextRope API SHALL express positions as `Int` UTF-16 code unit offsets and ranges as half-open `Range<Int>` over UTF-16 code units.

#### Scenario: TextRope target builds with no dependencies
- **WHEN** `swift build --target TextRope` is executed
- **THEN** the target compiles successfully with zero external dependency imports

#### Scenario: TextRope sources are Foundation-free
- **WHEN** the files under `Sources/TextRope/` are searched for `import Foundation`, `NSRange`, or `NSString`
- **THEN** no source code match exists

#### Scenario: TextRope public API uses stdlib range types only
- **WHEN** the public API surface of the `TextRope` target is enumerated
- **THEN** every range-taking or range-returning member uses `Range<Int>` or `Int`, and no signature names a Foundation type

#### Scenario: TextRopeTests target exists
- **WHEN** `swift test --filter TextRopeTests` is executed
- **THEN** the test target compiles and runs, depending only on `TextRope`

## ADDED Requirements

### Requirement: TextBuffer provides the NSRange convenience surface for TextRope

The `TextBuffer` target SHALL define public extensions on `TextRope` that provide the NSRange-based API removed from the `TextRope` target: `content(in: NSRange) -> String`, `delete(in: NSRange)`, and `replace(range: NSRange, with: String)`, each behaviorally identical to the corresponding `Range<Int>` primitive applied to `location ..< location + length`. The `TextBuffer` target SHALL also provide the composed-character-sequence APIs `composedCharacterSequences(in: NSRange) -> String` and `composedCharacterSequence(at: Int) -> String` as extensions on `TextRope`. A consumer importing only `TextBuffer` (which re-exports `TextRope`) SHALL see this combined API surface without a separate import. The NSRange forms MUST validate their arguments before conversion: a range whose `location` is `NSNotFound` or negative, or whose `length` is negative, MUST cause a precondition failure.

#### Scenario: TextBuffer consumer uses the NSRange API unchanged
- **WHEN** a module imports only `TextBuffer` and calls `rope.replace(range: NSRange(location: 0, length: 5), with: "hi")` on a `TextRope` containing `"hello world"`
- **THEN** the call compiles without a Foundation-specific TextRope import and `rope.content` is `"hi world"`

#### Scenario: NSRange convenience equals the Range primitive
- **WHEN** any of `content(in:)`, `delete(in:)`, or `replace(range:with:)` is called with `NSRange(location: l, length: n)` on one copy of a rope, and the `Range<Int>` primitive is called with `l ..< l + n` on an identical copy
- **THEN** both produce identical results — same returned string, same resulting `content`, `utf16Count`, and summaries

#### Scenario: Composed-sequence reads are available through TextBuffer
- **WHEN** a module imports only `TextBuffer` and calls `rope.composedCharacterSequence(at: 1)` on a `TextRope` containing `"a🎉b"`
- **THEN** the result is `"🎉"`

#### Scenario: Invalid NSRange traps at the convenience layer
- **WHEN** an NSRange convenience method is called with `location == NSNotFound`, a negative `location`, or a negative `length`
- **THEN** a precondition failure MUST occur
