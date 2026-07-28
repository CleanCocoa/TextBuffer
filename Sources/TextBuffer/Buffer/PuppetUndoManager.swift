import Foundation

@MainActor
protocol PuppetUndoManagerDelegate: AnyObject {
    func puppetUndo()
    func puppetRedo()
    var puppetCanUndo: Bool { get }
    var puppetCanRedo: Bool { get }
    var puppetUndoActionName: String { get }
    var puppetRedoActionName: String { get }
}

/// An `UndoManager` subclass that delegates undo and redo to its owner's ``OperationLog``.
///
/// You don't create instances directly. Instead, call
/// ``TransferableUndoable/enableSystemUndoIntegration()`` or
/// ``NSTextViewOperationLogBridge/enableSystemUndoIntegration()`` to obtain one. Assign the
/// returned undo manager to your window or document to enable AppKit's Edit menu undo/redo
/// items, or return it from `NSTextViewDelegate.undoManager(for:)` — the text view consults
/// that delegate method only while `allowsUndo == true`, and the native typing-undo
/// registrations that `allowsUndo` enables are swallowed here, so the owner's log stays the
/// only undo authority.
@MainActor
public final class PuppetUndoManager: UndoManager {
    weak var owner: (any PuppetUndoManagerDelegate)?

    init(owner: any PuppetUndoManagerDelegate) {
        self.owner = owner
        super.init()
        groupsByEvent = false
        super.beginUndoGrouping()
    }

    public override func undo() {
        owner?.puppetUndo()
    }

    public override func redo() {
        owner?.puppetRedo()
    }

    public override var canUndo: Bool {
        owner?.puppetCanUndo ?? false
    }

    public override var canRedo: Bool {
        owner?.puppetCanRedo ?? false
    }

    public override var undoActionName: String {
        owner?.puppetUndoActionName ?? ""
    }

    public override var redoActionName: String {
        owner?.puppetRedoActionName ?? ""
    }

    public override func registerUndo(withTarget target: Any, selector: Selector, object: Any?) {}

    public override func __registerUndoWithTarget(_ target: Any, handler: @escaping @MainActor (Any) -> Void) {}

    public override func prepare(withInvocationTarget target: Any) -> Any {
        invocationSwallower
    }

    private let invocationSwallower = SwallowingInvocationTarget()
}

/// Absorbs invocation-based undo registration: any selector message no-ops and returns `nil`,
/// so callers of `prepare(withInvocationTarget:)` can invoke their own selectors on the result
/// without crashing and without recording anything.
///
/// An `NSObject` subclass resolving unknown selectors dynamically, not the classic `NSProxy`
/// with `forwardInvocation:`, because `NSInvocation` and `NSMethodSignature` are unavailable
/// in Swift.
private final class SwallowingInvocationTarget: NSObject {
    override class func resolveInstanceMethod(_ sel: Selector) -> Bool {
        let swallow: @convention(block) (AnyObject) -> AnyObject? = { _ in nil }
        class_addMethod(self, sel, imp_implementationWithBlock(swallow), "@@:")
        return true
    }
}
