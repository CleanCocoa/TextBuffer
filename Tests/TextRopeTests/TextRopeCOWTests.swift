import XCTest
@testable import TextRope

final class TextRopeCOWTests: XCTestCase {
    func testCopySharesRoot() {
        var rope = TextRope()
        rope.root = .leaf("hello")
        let copy = rope
        XCTAssertTrue(copy.root === rope.root)
    }

    func testMutatingCopyDoesNotAffectOriginal() {
        var rope = TextRope()
        rope.root = .leaf("hello")
        var copy = rope
        copy.ensureUnique()
        copy.root = .leaf("world")
        XCTAssertEqual(rope.content, "hello")
        XCTAssertEqual(copy.content, "world")
    }

    func testEnsureUniqueOnUniqueIsNoop() {
        var rope = TextRope()
        rope.root = .leaf("hello")
        let before = Unmanaged.passUnretained(rope.root).toOpaque()
        rope.ensureUnique()
        let after = Unmanaged.passUnretained(rope.root).toOpaque()
        XCTAssertEqual(before, after)
    }

    func testEnsureUniqueOnSharedCopiesRoot() {
        var rope = TextRope()
        rope.root = .leaf("hello")
        let original = rope
        var copy = rope
        copy.ensureUnique()
        XCTAssertTrue(copy.root !== original.root)
        XCTAssertEqual(copy.content, original.content)
    }

    func testEnsureUniqueChildCopiesSharedChild() {
        let sharedChild = TextRope.Node.leaf("child")
        let extraRef = sharedChild
        let parent = TextRope.Node.inner(ContiguousArray([sharedChild]))
        let childBefore = parent.children[0]
        parent.ensureUniqueChild(at: 0)
        XCTAssertTrue(parent.children[0] !== childBefore)
        XCTAssertEqual(parent.children[0].chunk, "child")
        _ = extraRef
    }

    func testEnsureUniqueChildKeepsUniqueChild() {
        let parent = TextRope.Node.inner(ContiguousArray([.leaf("only")]))
        let pointerBefore = Unmanaged.passUnretained(parent.children[0]).toOpaque()
        parent.ensureUniqueChild(at: 0)
        let pointerAfter = Unmanaged.passUnretained(parent.children[0]).toOpaque()
        XCTAssertEqual(pointerBefore, pointerAfter)
    }
}
