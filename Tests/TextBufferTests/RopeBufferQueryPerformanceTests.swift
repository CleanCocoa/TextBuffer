//  Copyright © 2026 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

/// Perf ratio guards for the windowed text-analysis queries (change `rope-log-queries`),
/// mirroring `testBulkInsertCostGrowsLinearlyWithInsertedLength`'s discipline: a size-
/// independent query costs the same on a 1 MiB and a 4 MiB many-short-lines document
/// (ratio ≈1×), while full-document materialization scales with the document (≈4×).
/// Optional guard, droppable if unstable on CI; skips below the noise floor.
@available(macOS, introduced: 13.0)
final class RopeBufferQueryPerformanceTests: XCTestCase {

    /// 32-unit lines of space-separated short words.
    private func manyShortLinesDocument(bytes: Int) -> String {
        let line = "lorem ipsum dolor sit amet abcd\n"
        precondition(line.utf16.count == 32)
        return String(repeating: line, count: bytes / 32)
    }

    private static let callsPerMeasurement = 500

    /// Best-of-3 total time for `callsPerMeasurement` calls of `query` at a zero-length
    /// mid-document range (inside a word, inside a line).
    private func measuredQueryTime(
        documentLength: Int,
        _ query: (NSRange) throws -> NSRange
    ) rethrows -> Duration {
        let clock = ContinuousClock()
        // Mid-document, 10 units into a 32-unit line: inside a word, away from delimiters.
        let midRange = NSRange(location: (documentLength / 2 / 32) * 32 + 10, length: 0)
        var best = Duration.seconds(1000)
        for _ in 0..<3 {
            let elapsed = try clock.measure {
                for _ in 0..<Self.callsPerMeasurement {
                    _ = try query(midRange)
                }
            }
            best = min(best, elapsed)
        }
        return best
    }

    private func assertQueryCostIsSizeIndependent(
        queryName: String,
        _ makeQuery: (String) -> (NSRange) throws -> NSRange,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let smallDocument = manyShortLinesDocument(bytes: 1 << 20)
        let largeDocument = manyShortLinesDocument(bytes: 4 << 20)

        let smallQuery = makeQuery(smallDocument)
        let largeQuery = makeQuery(largeDocument)

        _ = try measuredQueryTime(documentLength: smallDocument.utf16.count, smallQuery) // warm-up

        let small = try measuredQueryTime(documentLength: smallDocument.utf16.count, smallQuery)
        let large = try measuredQueryTime(documentLength: largeDocument.utf16.count, largeQuery)

        try XCTSkipIf(small < .milliseconds(1), "1 MiB baseline (\(small)) is below the noise floor; the ratio would be meaningless")
        XCTAssertLessThan(large / small, 2.0, "\(queryName): 4 MiB took \(large) vs \(small) for 1 MiB — full-document materialization scales ≈4×, a size-independent query ≈1×", file: file, line: line)
    }

    func testLineRangePerCallCostIsIndependentOfDocumentSizeOnRopeBuffer() throws {
        try assertQueryCostIsSizeIndependent(queryName: "RopeBuffer.lineRange") { document in
            let buffer = RopeBuffer(document)
            return { try buffer.lineRange(for: $0) }
        }
    }

    func testLineRangePerCallCostIsIndependentOfDocumentSizeOnSendableRopeBuffer() throws {
        try assertQueryCostIsSizeIndependent(queryName: "SendableRopeBuffer.lineRange") { document in
            let buffer = SendableRopeBuffer(document)
            return { try buffer.lineRange(for: $0) }
        }
    }

    func testWordRangePerCallCostIsIndependentOfDocumentSizeOnRopeBuffer() throws {
        try assertQueryCostIsSizeIndependent(queryName: "RopeBuffer.wordRange") { document in
            let buffer = RopeBuffer(document)
            return { try buffer.wordRange(for: $0) }
        }
    }

    func testWordRangePerCallCostIsIndependentOfDocumentSizeOnSendableRopeBuffer() throws {
        try assertQueryCostIsSizeIndependent(queryName: "SendableRopeBuffer.wordRange") { document in
            let buffer = SendableRopeBuffer(document)
            return { try buffer.wordRange(for: $0) }
        }
    }
}
