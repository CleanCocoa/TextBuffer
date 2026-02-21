//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

// NOTE: Property-like requirements use method names (`getContent()`, `getRange()`,
// `getSelectedRange()`) instead of matching Buffer's property names. This works
// around a Swift SIL bug (as of 6.2.3 and 6.3-dev 2026-02-19) where protocol
// refinement with sync property redeclarations causes SILGen to resolve witness
// lookups through the base protocol's async entries, crashing the compiler with:
//   "SIL verification failed: cannot call an async function from a non async function"
// TODO: Retry property-style requirements with Swift 6.4.
// Bug report: https://github.com/swiftlang/swift/issues/62221

public protocol AsyncBuffer: AnyObject {
    typealias Location = UTF16Offset
    typealias Length = UTF16Length
    typealias Range = UTF16Range
    typealias Content = String

    // Workaround: `getX()` methods instead of `var x` properties.
    // Using property names matching Buffer's (`content`, `range`,
    // `selectedRange`) triggers a Swift SIL bug; see file header.
    func getContent() async -> Content
    func getRange() async -> Range
    func getSelectedRange() async -> Range

    func setSelectedRange(_ range: Range) async
    func getInsertionLocation() async -> Location
    func setInsertionLocation(_ location: Location) async

    func select(_ range: Range) async
    func lineRange(for searchRange: Range) async throws -> Range
    func wordRange(for searchRange: Range) async throws -> Range
    func character(at location: Location) async throws -> Content
    func content(in subrange: Range) async throws -> Content
    func unsafeCharacter(at location: Location) async -> Content
    func insert(_ content: Content, at location: Location) async throws
    func insert(_ content: Content) async throws
    func delete(in deletedRange: Range) async throws
    func replace(range replacementRange: Range, with content: Content) async throws
    func modifying<T>(affectedRange: Range, _ block: () -> T) async throws -> T
}

import Foundation

extension AsyncBuffer {
    @inlinable
    public func getInsertionLocation() async -> Location {
        await getSelectedRange().location
    }

    @inlinable
    public func setInsertionLocation(_ location: Location) async {
        await setSelectedRange(Range(location: location, length: 0))
    }

    @inlinable
    public func select(_ range: Range) async {
        await setSelectedRange(range)
    }

    @inlinable
    public func insert(_ content: Content) async throws {
        try await replace(range: await getSelectedRange(), with: content)
    }

    @inlinable
    public func character(at location: Location) async throws -> Content {
        try await self.content(in: Range(location: location, length: 1))
    }

    @inlinable
    public func getIsSelectingText() async -> Bool {
        await getSelectedRange().length > 0
    }
}
