import Foundation

extension TransferableUndoable {
    public func sendableSnapshot() -> SendableRopeBuffer {
        var srb = SendableRopeBuffer(content)
        srb.selectedRange = selectedRange
        srb.log = log
        return srb
    }

    public func represent(_ snapshot: SendableRopeBuffer) {
        precondition(!log.isGrouping, "represent(_:) called while an undo group is open")
        do {
            try replace(range: range, with: snapshot.content)
        } catch {
            preconditionFailure("TransferableUndoable invariant violated: represent(_:) failed to replace buffer content — \(error)")
        }
        selectedRange = snapshot.selectedRange
        log = snapshot.log
    }
}
