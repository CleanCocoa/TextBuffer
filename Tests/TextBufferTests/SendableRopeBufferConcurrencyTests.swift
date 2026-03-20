import XCTest
import TextBuffer

final class SendableRopeBufferConcurrencyTests: XCTestCase {

    func testTaskGroupParallelReplace() async throws {
        let template = SendableRopeBuffer("Hello, NAME!")

        let results = await withTaskGroup(
            of: (Int, SendableRopeBuffer).self,
            returning: [(Int, SendableRopeBuffer)].self
        ) { group in
            for i in 0..<1000 {
                var buffer = template
                group.addTask {
                    try! buffer.replace(
                        range: NSRange(location: 7, length: 4),
                        with: "User\(i)"
                    )
                    return (i, buffer)
                }
            }
            var collected: [(Int, SendableRopeBuffer)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.count, 1000)
        for (i, buffer) in results {
            XCTAssertEqual(buffer.content, "Hello, User\(i)!")
        }
    }

    func testUndoWorksAfterCrossIsolationTransfer() async throws {
        var buffer = SendableRopeBuffer("original")
        try buffer.replace(range: NSRange(location: 0, length: 8), with: "modified")

        let snapshot = buffer
        let undone: SendableRopeBuffer = await Task.detached {
            var b = snapshot
            _ = b.undo()
            return b
        }.value

        XCTAssertEqual(undone.content, "original")
        XCTAssertEqual(buffer.content, "modified")
    }

    func testParallelMutationsAreIndependent() async throws {
        var base = SendableRopeBuffer("base")
        try base.insert(" text", at: 4)

        let results = await withTaskGroup(
            of: String.self,
            returning: [String].self
        ) { group in
            for i in 0..<100 {
                let snapshot = base
                group.addTask {
                    var local = snapshot
                    try! local.insert(" \(i)", at: local.range.length)
                    return local.content
                }
            }
            var collected: [String] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        XCTAssertEqual(results.count, 100)
        XCTAssertEqual(base.content, "base text")

        for result in results {
            XCTAssertTrue(result.hasPrefix("base text "))
        }
    }
}
