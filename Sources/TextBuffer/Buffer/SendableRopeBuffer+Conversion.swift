import Foundation

extension SendableRopeBuffer {
    public init<B: TextBuffer>(
        copying buffer: B
    ) where B.Range == NSRange, B.Content == String {
        self.init(buffer.content)
        self.selectedRange = buffer.selectedRange
    }

    @MainActor
    public init<B: Buffer>(
        from transferable: TransferableUndoable<B>
    ) where B.Range == NSRange, B.Content == String {
        self.init(transferable.content)
        self.selectedRange = transferable.selectedRange
        self.log = transferable.log
    }

    public func toRopeBuffer() -> RopeBuffer {
        let rb = RopeBuffer(content)
        rb.selectedRange = selectedRange
        return rb
    }

    @MainActor
    public func toTransferableUndoable() -> TransferableUndoable<RopeBuffer> {
        let rb = toRopeBuffer()
        return TransferableUndoable(rb, log: log)
    }
}
