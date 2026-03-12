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

    public override func prepare(withInvocationTarget target: Any) -> Any {
        self
    }
}
