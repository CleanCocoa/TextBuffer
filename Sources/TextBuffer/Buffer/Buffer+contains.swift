//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation

extension TextBuffer {
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
