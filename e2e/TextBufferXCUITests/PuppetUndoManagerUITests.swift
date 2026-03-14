import XCTest

final class PuppetUndoManagerUITests: UITestBase {
    var textView: XCUIElement {
        app.textViews["tb.editor.textView"]
    }

    func testUndoViaCommandZ() {
        textView.click()
        textView.typeText("Hello")
        XCTAssertEqual(textView.value as? String, "Hello")

        textView.typeKey("z", modifierFlags: .command)

        XCTAssertEqual(textView.value as? String, "")
    }

    func testRedoViaCommandShiftZ() {
        textView.click()
        textView.typeText("Hello")
        textView.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(textView.value as? String, "")

        textView.typeKey("z", modifierFlags: [.command, .shift])

        XCTAssertEqual(textView.value as? String, "Hello")
    }

    func testEditMenuReflectsUndoState() {
        textView.click()
        textView.typeText("Hello")

        let editMenu = app.menuBars.menuBarItems["Edit"]
        editMenu.click()
        let undoItem = editMenu.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Undo'")).firstMatch
        XCTAssertTrue(undoItem.isEnabled)
        editMenu.typeKey(.escape, modifierFlags: [])

        textView.typeKey("z", modifierFlags: .command)

        editMenu.click()
        let undoItemAfter = editMenu.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Undo'")).firstMatch
        XCTAssertFalse(undoItemAfter.isEnabled)
        editMenu.typeKey(.escape, modifierFlags: [])
    }

    func testUndoActionNameInEditMenu() {
        textView.click()
        textView.typeText("Hello")

        let editMenu = app.menuBars.menuBarItems["Edit"]
        editMenu.click()
        let undoItem = editMenu.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Undo'")).firstMatch
        XCTAssertTrue(undoItem.exists)
        editMenu.typeKey(.escape, modifierFlags: [])
    }
}
