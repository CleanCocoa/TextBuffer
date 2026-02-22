//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import TextBuffer
import Foundation

struct TestRange: BufferRange, Equatable {
    typealias Position = Int
    var location: Int
    var length: Int
    init(location: Int, length: Int) {
        self.location = location
        self.length = length
    }
    func subtracting(_ other: TestRange) -> TestRange { fatalError() }
    mutating func subtract(_ other: TestRange) { fatalError() }
}
