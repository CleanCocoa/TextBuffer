//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import Foundation
import XCTest
import TextBuffer

/// Asserts that a buffer's content and selection match the expected string representation.
///
/// Uses the `«selection»` and `ˇ` notation from `MutableStringBuffer.description`.
///
/// ```swift
/// assertBufferState(buffer, "Hello «World»")
/// assertBufferState(buffer, "Helloˇ World")
/// ```
public func assertBufferState<B: TextBuffer>(
    _ buffer: B,
    _ expectedDescription: String,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #filePath, line: UInt = #line
) where B.Range == NSRange, B.Content == String {
    XCTAssertEqual(
        MutableStringBuffer(copying: buffer).description,
        expectedDescription,
        message(),
        file: file, line: line
    )
}
