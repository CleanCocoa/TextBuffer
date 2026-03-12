import Foundation

public enum BufferStep {
    case insert(content: String, at: Int)
    case delete(range: NSRange)
    case replace(range: NSRange, with: String)
    case select(NSRange)
    case undo
    case redo
    indirect case group(actionName: String?, steps: [BufferStep])
}
