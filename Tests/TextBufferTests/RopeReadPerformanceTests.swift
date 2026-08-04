//  Copyright © 2026 Christian Tietze. All rights reserved. Distributed under the MIT License.

import XCTest
import TextBuffer

/// Performance instruments for the rope-backed point read (`perf-read-fast-path`, DEF-011
/// read half):
///
/// 1. A **comparative measurement** of `unsafeCharacter(at:)` on `RopeBuffer` versus
///    `MutableStringBuffer` per content class, reported through the test log in the
///    `TextRopeStressTests` summary-print style and never asserted — cross-implementation
///    wall-clock ratios vary across machines and toolchains, so a threshold would be
///    either meaningless or flaky. Before/after numbers are recorded in the change's
///    tasks.md and the CHANGELOG.
/// 2. A **size-independence ratio pin** (asserted): per-call cost must not scale with
///    document size. This test is green on the pre-fast-path windowed implementation too
///    (the ±128-unit window is a fixed constant; only the O(log n) descent grows) — it is
///    the permanent regression pin for the navigation spec's performance scenario, not a
///    red test.
final class RopeReadPerformanceTests: XCTestCase {

    private static let comparativeBatchSize = 20_000
    private static let sizeRatioBatchSize = 50_000

    private static func asciiDocument(utf16Count: Int) -> String {
        let sentence = "The quick brown fox jumps over the lazy dog 0123456789 ABC. " // 61 units
        var result = String(repeating: sentence, count: utf16Count / sentence.utf16.count)
        result += String(repeating: "x", count: utf16Count - result.utf16.count)
        return result
    }

    /// Offsets for a fixed number of calls, spread proportionally across the document.
    private static func spreadOffsets(utf16Count: Int, batchSize: Int) -> [Int] {
        (0..<batchSize).map { $0 * utf16Count / batchSize }
    }

    private static func nanosecondsPerCall(_ duration: Duration, batchSize: Int) -> Double {
        let nanoseconds = Double(duration.components.seconds) * 1e9
            + Double(duration.components.attoseconds) / 1e9
        return nanoseconds / Double(batchSize)
    }

    /// Best-of-3 total time for one batch of `unsafeCharacter(at:)` calls, after one
    /// warm-up round (the `testBulkInsertCostGrowsLinearlyWithInsertedLength` discipline).
    private static func measure(_ offsets: [Int], _ read: (Int) -> String) -> Duration {
        let clock = ContinuousClock()
        _ = clock.measure { for offset in offsets { _ = read(offset) } } // warm-up
        var best = Duration.seconds(1000)
        for _ in 0..<3 {
            let elapsed = clock.measure { for offset in offsets { _ = read(offset) } }
            best = min(best, elapsed)
        }
        return best
    }

    // MARK: - Comparative measurement (reported, never asserted)

    /// Reports per-call time of rope-backed `unsafeCharacter(at:)` against
    /// `MutableStringBuffer.unsafeCharacter(at:)` on identical documents per content
    /// class. No assertions on the cross-implementation ratio by design — this is the
    /// recorded evidence for DEF-011's read half, not a regression gate.
    func testComparativeUnsafeCharacterReadReport() {
        let documents: [(label: String, string: String)] = [
            ("ascii ~1 MiB", Self.asciiDocument(utf16Count: 1 << 20)),
            // Surrogate pairs and a ZWJ chain: 😀 (2 units) + 👨‍👩‍👧‍👦 (11 units) per repeat.
            ("emoji-heavy", String(repeating: "😀👨‍👩‍👧‍👦", count: 20_000)),
            // Regional-indicator runs of 64 flags (256 units), each bracketed by a space
            // so no run exceeds the rope's 4,096-unit backward-walk cap.
            ("regional-indicator runs", String(repeating: String(repeating: "🇩🇪", count: 64) + " ", count: 200)),
        ]
        for document in documents {
            let offsets = Self.spreadOffsets(
                utf16Count: document.string.utf16.count,
                batchSize: Self.comparativeBatchSize
            )
            let rope = RopeBuffer(document.string)
            let oracle = MutableStringBuffer(document.string)
            let ropeTime = Self.measure(offsets) { rope.unsafeCharacter(at: $0) }
            let oracleTime = Self.measure(offsets) { oracle.unsafeCharacter(at: $0) }
            let ropeNs = Self.nanosecondsPerCall(ropeTime, batchSize: Self.comparativeBatchSize)
            let oracleNs = Self.nanosecondsPerCall(oracleTime, batchSize: Self.comparativeBatchSize)
            print(String(
                format: "RopeReadPerformance: %@ (%d units) — RopeBuffer %.0f ns/call, MutableStringBuffer %.0f ns/call, ratio %.2f×",
                document.label, document.string.utf16.count, ropeNs, oracleNs, ropeTime / oracleTime
            ))
        }
    }

    // MARK: - Size-independence ratio pin (asserted)

    /// Permanent regression pin for the navigation spec's performance scenario: the same
    /// fixed batch of point reads on a 4 MiB ASCII document must not cost meaningfully
    /// more than on a 1 MiB one. Document-proportional work would predict ≈4×; per-call
    /// constant cost ≈1×; the O(log n) descent ≈1.1×. The 2× bound is generous against
    /// both honest models and far from the failure model. Green before and after the
    /// fast path — the windowed path's ±128-unit window is already a fixed per-call
    /// constant. Skips below the noise floor per the insert ratio test's discipline.
    func testPointReadCostIsIndependentOfDocumentSize() throws {
        func measuredBatch(utf16Count: Int) -> Duration {
            let rope = RopeBuffer(Self.asciiDocument(utf16Count: utf16Count))
            let offsets = Self.spreadOffsets(utf16Count: utf16Count, batchSize: Self.sizeRatioBatchSize)
            return Self.measure(offsets) { rope.unsafeCharacter(at: $0) }
        }

        let small = measuredBatch(utf16Count: 1 << 20)
        let large = measuredBatch(utf16Count: 4 << 20)

        print(String(format: "RopeReadPerformance: size independence — 1 MiB batch \(small), 4 MiB batch \(large), ratio %.2f×", large / small))
        try XCTSkipIf(small < .milliseconds(2), "1 MiB baseline (\(small)) is below the noise floor; the ratio would be meaningless")
        XCTAssertLessThan(
            large / small, 2.0,
            "the batch took \(large) on 4 MiB vs \(small) on 1 MiB — document-proportional work would predict ≈4×, constant per-call cost ≈1× (log-descent ≈1.1×)"
        )
    }
}
