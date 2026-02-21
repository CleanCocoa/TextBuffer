//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

/// Base protocol for asynchronous text buffer access, refined by ``Buffer`` for synchronous use.
///
/// Buffers are reference types (`AnyObject`) with mutable state. The primary associated type
/// `Range` determines the range representation (e.g., `NSRange` for UTF-16 code unit offsets).
/// `Location` is derived as `Range.Position`.
///
/// ## SIL Compiler Bug Workaround
///
/// Property-like requirements use method names (`getContent()`, `getRange()`, `getSelectedRange()`)
/// instead of matching ``Buffer``'s property names. When `Buffer: AsyncBuffer` redeclares the same
/// property names (e.g., both have `var range: Range`), SILGen incorrectly resolves **all** witness
/// lookups through `AsyncBuffer`'s async entries, crashing the compiler with:
///
/// ```
/// SIL verification failed: cannot call an async function from a non async function
/// ```
///
/// Affected Swift versions: 6.2.3, 6.3-dev (2026-02-19).
/// Bug report: <https://github.com/swiftlang/swift/issues/62221>
///
/// - TODO: Retry property-style requirements with Swift 6.4.
public protocol AsyncBuffer<Range>: AnyObject {
    /// The range type used for addressing spans within the buffer.
    associatedtype Range: BufferRange

    /// The position/index type, derived from ``Range``.
    typealias Location = Range.Position

    /// Fixed to `UTF16Length` (`Int`). All length measurements use UTF-16 code units.
    typealias Length = Int

    /// The content type returned by read operations. Conformers set this to their backing store type
    /// (e.g., `String`, `NSAttributedString`, rope). Write operations always accept `String`.
    associatedtype Content

    /// Returns the full text content of the buffer.
    func getContent() async -> Content
    /// Returns the full range of the buffer's content.
    func getRange() async -> Range
    /// Returns the currently selected range.
    func getSelectedRange() async -> Range

    /// Sets the selected range.
    func setSelectedRange(_ range: Range) async
    /// Returns the current insertion location (start of the selected range).
    func getInsertionLocation() async -> Location
    /// Sets the insertion location.
    func setInsertionLocation(_ location: Location) async

    /// Changes the selected range.
    func select(_ range: Range) async
    /// Returns a character-wide slice of content at `location`.
    func character(at location: Location) async throws(BufferAccessFailure) -> Content
    /// Returns a slice of content within `subrange`.
    func content(in subrange: Range) async throws(BufferAccessFailure) -> Content
    /// Returns a character at `location` without bounds checking.
    func unsafeCharacter(at location: Location) async -> Content
    /// Inserts `content` at `location` without affecting the selected range.
    func insert(_ content: String, at location: Location) async throws(BufferAccessFailure)
    /// Inserts `content` like typing at the current insertion location.
    func insert(_ content: String) async throws(BufferAccessFailure)
    /// Deletes content in `deletedRange`.
    func delete(in deletedRange: Range) async throws(BufferAccessFailure)
    /// Replaces content in `replacementRange` with `content`.
    func replace(range replacementRange: Range, with content: String) async throws(BufferAccessFailure)
    /// Wraps changes to `affectedRange` inside `block` to bundle updates.
    func modifying<T>(affectedRange: Range, _ block: () -> T) async throws(BufferAccessFailure) -> T
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
    public func insert(_ content: String) async throws(BufferAccessFailure) {
        try await replace(range: await getSelectedRange(), with: content)
    }

    @inlinable
    public func character(at location: Location) async throws(BufferAccessFailure) -> Content {
        try await self.content(in: Range(location: location, length: 1))
    }

    @inlinable
    public func getIsSelectingText() async -> Bool {
        await getSelectedRange().length > 0
    }
}
