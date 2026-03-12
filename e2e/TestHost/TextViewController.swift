import AppKit
import TextBuffer

final class TextViewController: NSViewController, NSTextViewDelegate {
    private(set) var textView: NSTextView!
    private var scrollView: NSScrollView!
    private var buffer: TransferableUndoable<NSTextViewBuffer>!
    private var puppet: UndoManager!

    override func loadView() {
        scrollView = NSTextView.scrollableTextView()
        textView = scrollView.documentView as? NSTextView
        textView.setAccessibilityIdentifier("tb.editor.textView")
        textView.allowsUndo = false
        textView.isRichText = false
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.delegate = self
        view = scrollView
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        let nsTextViewBuffer = NSTextViewBuffer(textView: textView)
        buffer = TransferableUndoable(nsTextViewBuffer)
        puppet = buffer.enableSystemUndoIntegration()
    }

    func undoManager(for view: NSTextView) -> UndoManager? {
        puppet
    }
}
