import Foundation

public struct BufferOperation: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case insert(content: String, at: Int)
        case delete(range: NSRange, deletedContent: String)
        case replace(range: NSRange, oldContent: String, newContent: String)
    }

    public var kind: Kind

    public init(kind: Kind) {
        self.kind = kind
    }
}
