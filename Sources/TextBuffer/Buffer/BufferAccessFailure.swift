//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

/// Error thrown by ``Buffer`` operations when access would be out of range or a modification is forbidden.
public struct BufferAccessFailure: Error, Sendable {
    public let label: String
    public let context: String?
    public let underlyingError: Error?

    fileprivate init(
        label: String,
        context: String? = nil,
        underlyingError: Error? = nil
    ) {
        self.label = label
        self.context = context
        self.underlyingError = underlyingError
    }

    /// Thrown when `requested` range falls outside the `available` buffer range.
    public static func outOfRange(
        requested: UTF16Range,
        available: UTF16Range
    ) -> BufferAccessFailure {
        return BufferAccessFailure(
            label: "out of range",
            context: "tried to access (\(requested.location)..<\(requested.endLocation)) in available range (\(available.location)..<\(available.endLocation))"
        )
    }

    /// Thrown when a single `location` (with optional `length`) falls outside the `available` buffer range.
    public static func outOfRange(
        location: UTF16Offset,
        length: UTF16Length = 0,
        available: UTF16Range
    ) -> BufferAccessFailure {
        return outOfRange(
            requested: .init(location: location, length: length),
            available: available
        )
    }

    /// Thrown when a modification to `requestedRange` is rejected by the buffer (e.g., via `shouldChangeText`).
    public static func modificationForbidden(
        in requestedRange: UTF16Range
    ) -> BufferAccessFailure {
        BufferAccessFailure(
            label: "modification not allowed",
            context: "tried to modify (\(requestedRange.location)..<\(requestedRange.endLocation))"
        )
    }

    /// Wraps any `Error` as a `BufferAccessFailure`, passing through existing `BufferAccessFailure` values unchanged.
    public static func wrap(_ error: any Error) -> BufferAccessFailure {
        return error as? BufferAccessFailure
          ?? BufferAccessFailure(
            label: "",
            context: error.localizedDescription,
            underlyingError: error
          )
    }
}

extension BufferAccessFailure: CustomDebugStringConvertible {
    public var debugDescription: String {
        return [
            label,
            (context ?? ""),
            // Do not include underlyingError here: we expect an error to be wrapped via `wrap(_:)`, which includes the wrapped errors description in `context`.
        ].filter(\.isEmpty.inverted).joined(separator: "\n")
    }
}
