import AppKit

@main
final class AppDelegate: NSObject, NSApplicationDelegate {
    var window: NSWindow!
    var viewController: TextViewController!

    func applicationDidFinishLaunching(_ notification: Notification) {
        viewController = TextViewController()

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "TextBuffer Test Host"
        window.contentViewController = viewController
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }
}
