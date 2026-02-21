//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation // For inlining isSelectingText as long as Buffer.Range is a typealias

extension Buffer {
    /// Returns `true` if `range` lies within the buffer's bounds. Works for all ``BufferRange`` types.
    @inlinable @inline(__always)
    public func contains(
        range: Range
    ) -> Bool {
        return self.range.contains(range)
    }
}

extension AsyncBuffer {
    @inlinable
    public func contains(range: Range) async -> Bool {
        return await self.getRange().contains(range)
    }
}
