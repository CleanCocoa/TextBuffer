//  Copyright © 2024 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

final class BufferWithSelectionFromStringTests: XCTestCase {
    func testBufferFromPlainString() throws {
        XCTAssertEqual(try makeBuffer("hello\nworld"), MutableStringBuffer("hello\nworld"))
    }

    func testBufferWithSelectedRange() throws {
        let expectedBuffer = MutableStringBuffer("0123456")
        expectedBuffer.selectedRange = .init(location: 1, length: 2)
        XCTAssertEqual(try makeBuffer("0«12»3456"), expectedBuffer)
    }

    func testBufferWithInsertionPoint() throws {
        let expectedBuffer = MutableStringBuffer("0123456")
        expectedBuffer.selectedRange = .init(location: 4, length: 0)
        XCTAssertEqual(try makeBuffer("0123ˇ456"), expectedBuffer)
    }

    func testChangeBuffer() throws {
        var buffer = MutableStringBuffer("hello\nworld")

        try change(buffer: &buffer, to: "go«od»bye")
        assertBufferState(buffer, "go«od»bye")

        try change(buffer: &buffer, to: "")
        assertBufferState(buffer, "ˇ")
    }

    func testMakeSendableRopeBufferWithInsertionPoint() throws {
        let buffer = try makeSendableRopeBuffer("helloˇ world")
        XCTAssertEqual(buffer.content, "hello world")
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 5, length: 0))
    }

    func testMakeSendableRopeBufferWithSelection() throws {
        let buffer = try makeSendableRopeBuffer("hello «world»")
        XCTAssertEqual(buffer.content, "hello world")
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 6, length: 5))
    }

    func testMakeSendableRopeBufferWithEmoji() throws {
        let buffer = try makeSendableRopeBuffer("«🎉»party")
        XCTAssertEqual(buffer.content, "🎉party")
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 0, length: 2))
    }

    func testMakeSendableRopeBufferWithCJK() throws {
        let buffer = try makeSendableRopeBuffer("你好«世界»")
        XCTAssertEqual(buffer.content, "你好世界")
        XCTAssertEqual(buffer.selectedRange, NSRange(location: 2, length: 2))
    }
}
