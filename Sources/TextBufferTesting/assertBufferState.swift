//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

public func assertBufferState<B: Buffer>(
    _ buffer: B,
    _ expectedDescription: String,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath, line: UInt = #line
) where B.Range == UTF16Range {
    XCTAssertEqual(
        MutableStringBuffer(wrapping: buffer).description,
        expectedDescription,
        message(),
        file: file, line: line
    )
}
