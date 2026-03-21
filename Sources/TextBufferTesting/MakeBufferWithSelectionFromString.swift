//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation
import TextBuffer

/// Error thrown when a buffer string representation is malformed, e.g. with unmatched or nested `«»` markers.
public struct InvalidBufferStringRepresentation: Error {
    public let stringRepresentation: String
    public let parts: [String]
}

/// Test helper to create `MutableStringBuffer` from a string that matches the `debugDescription` format of either `"text «with selection»"` or `"text ˇinsertion point"`.
/// - Throws: `InvalidBufferStringRepresentation` if `stringRepresentation` is malformed.
@available(macOS, introduced: 13.0, message: "macOS 13 required for Regex")
public func makeBuffer(_ stringRepresentation: String) throws -> MutableStringBuffer {
    var buffer = MutableStringBuffer("")
    try change(buffer: &buffer, to: stringRepresentation)
    return buffer
}

/// Test helper to create a `SendableRopeBuffer` from a string using `«selection»` or `ˇ` notation.
/// - Throws: ``InvalidBufferStringRepresentation`` if `stringRepresentation` is malformed.
@available(macOS, introduced: 13.0, message: "macOS 13 required for Regex")
public func makeSendableRopeBuffer(_ stringRepresentation: String) throws -> SendableRopeBuffer {
    var buffer = SendableRopeBuffer("")
    try change(buffer: &buffer, to: stringRepresentation)
    return buffer
}

@available(*, deprecated, message: "Use change(buffer: &buffer, to:) with inout instead")
@available(macOS, introduced: 13.0, message: "macOS 13 required for Regex")
public func change<B: Buffer>(
    buffer: B,
    to stringRepresentation: String
) throws where B.Range == NSRange, B.Content == String {
    var buffer = buffer
    try changeBuffer(&buffer, to: stringRepresentation)
}

/// Replaces a buffer's content and selection to match the given string representation.
///
/// Uses `«selection»` for a selected range and `ˇ` for an insertion point.
/// - Throws: ``InvalidBufferStringRepresentation`` if `stringRepresentation` is malformed.
@available(macOS, introduced: 13.0, message: "macOS 13 required for Regex")
public func change<B: TextBuffer>(
    buffer: inout B,
    to stringRepresentation: String
) throws where B.Range == NSRange, B.Content == String {
    try changeBuffer(&buffer, to: stringRepresentation)
}

@available(macOS, introduced: 13.0, message: "macOS 13 required for Regex")
private func changeBuffer<B: TextBuffer>(
    _ buffer: inout B,
    to stringRepresentation: String
) throws where B.Range == NSRange, B.Content == String {
    /// Indices:
    /// - `0`: text before
    /// - `1`: text inside
    /// - `2`: text after
    let selectionParts = stringRepresentation
        .split(separator: try Regex("[«»]"), omittingEmptySubsequences: false)
        .map { String($0) }

    if selectionParts.count == 3 {
        try buffer.replace(range: buffer.range, with: selectionParts.joined(separator: ""))
        buffer.selectedRange = NSRange(
            location: selectionParts[0].utf16.count,
            length: selectionParts[1].utf16.count
        )
        return
    } else if selectionParts.count > 1 {
        // Nested or half-open selection
        throw InvalidBufferStringRepresentation(
            stringRepresentation: stringRepresentation,
            parts: selectionParts
        )
    }

    let insertionPointParts = stringRepresentation
        .split(separator: "ˇ", maxSplits: 2, omittingEmptySubsequences: false)
        .map { String($0) }
    try buffer.replace(range: buffer.range, with: insertionPointParts.joined(separator: ""))
    if stringRepresentation.contains("ˇ") {
        buffer.selectedRange = NSRange(
            location: insertionPointParts[0].utf16.count,
            length: 0
        )
    } else {
        // `replace(range:with:)` moves the insertion point to the end; reset to the beginning so the result is similar to `MutableStringBuffer.init`.
        buffer.insertionLocation = 0
    }
}
