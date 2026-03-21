//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

/// A type whose instances can report their length, used by buffer protocols to measure content.
///
/// `String` conforms to `BufferContent` with its `length` returning `utf16.count`,
/// matching Foundation's `NSString` indexing used throughout the buffer API.
public protocol BufferContent<Length> {
    associatedtype Length
    var length: Length { get }
}

extension String: BufferContent {
    @inlinable @inline(__always)
    public var length: Int { utf16.count }
}
