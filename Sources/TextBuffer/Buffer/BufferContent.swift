//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

public protocol BufferContent<Length> {
    associatedtype Length
    var length: Length { get }
}

extension String: BufferContent {
    @inlinable @inline(__always)
    public var length: Int { utf16.count }
}
