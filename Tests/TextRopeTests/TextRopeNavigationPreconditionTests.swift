import Testing
import Foundation
@testable import TextRope

@Suite struct TextRopeNavigationPreconditions {
    @Test func `finding a leaf traps when the offset exceeds the document length`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.findLeaf(utf16Offset: 6)
        }
    }

    @Test func `extracting content traps when the range end exceeds the document length`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: NSRange(location: 3, length: 5))
        }
    }

    // DEF-004: bounds validation precedes the zero-length early return.

    @Test func `extracting content traps for a zero-length range past the end`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: NSRange(location: 6, length: 0))
        }
    }

    @Test func `extracting content traps for a zero-length range at a negative location`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: NSRange(location: -1, length: 0))
        }
    }

    @Test func `extracting content traps for a zero-length range at NSNotFound`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: NSRange(location: NSNotFound, length: 0))
        }
    }

    @Test func `composed sequences trap for a zero-length range past the end`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.composedCharacterSequences(in: NSRange(location: 6, length: 0))
        }
    }

    @Test func `composed sequences trap for a zero-length range at a negative location`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.composedCharacterSequences(in: NSRange(location: -1, length: 0))
        }
    }

    @Test func `composed sequences trap for a zero-length range at NSNotFound`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.composedCharacterSequences(in: NSRange(location: NSNotFound, length: 0))
        }
    }

    // Range<Int> primitive: same trap behavior, half-open bounds.

    @Test func `extracting content with an Int range traps when the range end exceeds the document length`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: 3..<8)
        }
    }

    @Test func `extracting content with an Int range traps for a negative lowerBound`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: (-1)..<2)
        }
    }

    // DEF-004: bounds validation precedes the empty-range early return.

    @Test func `extracting content with an Int range traps for an empty range past the end`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: 500..<500)
        }
    }

    @Test func `extracting content with an Int range traps for an empty range at a negative offset`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.content(in: (-1) ..< (-1))
        }
    }

    // utf16CodeUnits(in:) bounds traps.

    @Test func `extracting code units traps when the range end exceeds the document length`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.utf16CodeUnits(in: 3..<8)
        }
    }

    @Test func `extracting code units traps for a negative lowerBound`() async {
        await #expect(processExitsWith: .failure) {
            let rope = TextRope("hello")
            _ = rope.utf16CodeUnits(in: (-1)..<2)
        }
    }
}
