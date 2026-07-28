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
}
