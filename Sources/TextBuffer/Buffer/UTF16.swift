//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation

extension NSRange {
    /// > Warning: Produces a runtime exception if you try to set `endLocation` to a value lower than `location`, which would produce a negative `length`.
    @inlinable
    public var endLocation: Int {
        get { upperBound }
        set {
            precondition(location <= newValue)
            length = newValue - location
        }
    }

    /// > Warning: Produces a runtime exception if you try to set `endLocation` to a value lower than `startLocation`, which would produce a negative `length`.
    @inlinable @inline(__always)
    public init(
        startLocation: Int,
        endLocation: Int
    ) {
        precondition(startLocation <= endLocation)
        self.init(location: startLocation, length: endLocation - startLocation)
    }
}
