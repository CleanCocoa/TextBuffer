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
}
