import XCTest

@MainActor
final class MacThreadListUITests: FixtureUITestCase {
    private func key(_ key: XCUIKeyboardKey) { app.typeKey(key, modifierFlags: []) }

    func testNativeSelectionArrowsReturnAndDeleteUseHostCallbacks() {
        launch("host-threads")
        activate(element("sessionRow-alpha"))
        wait(element("host-selection"), "label == 'Selection: alpha'")
        key(.downArrow)
        wait(element("host-selection"), "label == 'Selection: beta'")
        key(.upArrow)
        wait(element("host-selection"), "label == 'Selection: alpha'")
        key(.return)
        wait(element("host-open"), "label == 'Opened: alpha, Open calls: 1'")
        key(.delete)
        activate(app.buttons["cancel-alpha"])
        notice("Archive calls: 0, Delete calls: 0")
        XCTAssertTrue(element("sessionRow-alpha").exists)
        activate(element("sessionRow-alpha"))
        key(.delete)
        activate(app.buttons["confirm-alpha"])
        // A repeated keyboard command while pending must share the menu's controller, not open another dialog.
        key(.delete)
        notice("Archive calls: 0, Delete calls: 1")
        wait(element("sessionRow-alpha"), "exists == false")
        XCTAssertFalse(app.buttons["confirm-alpha"].exists)
        activate(element("sessionRow-read-only"))
        key(.delete)
        XCTAssertFalse(app.buttons["confirm-read-only"].exists)
        notice("Archive calls: 0, Delete calls: 1")
    }

    func testRightClickAndKeyboardDeleteShareErrorAndConfirmationState() {
        launch("host-threads")
        activate(app.checkBoxes["Fail next action"])
        let beta = element("sessionRow-beta")
        activate(beta)
        key(.delete)
        activate(app.buttons["confirm-beta"])
        let failure = app.staticTexts.matching(NSPredicate(format: "label == %@ OR value == %@",
                                                            "Host delete failed", "Host delete failed")).firstMatch
        XCTAssertTrue(failure.waitForExistence(timeout: 6))
        key(.delete)
        XCTAssertFalse(app.buttons["confirm-beta"].exists)
        activate(app.buttons["dismiss-beta"])
        XCTAssertTrue(beta.exists)
        beta.rightClick()
        activate(element("delete-beta"))
        activate(app.buttons["cancel-beta"])
        notice("Archive calls: 0, Delete calls: 1")
        activate(beta)
        key(.delete)
        activate(app.buttons["confirm-beta"])
        wait(beta, "exists == false")
        notice("Archive calls: 0, Delete calls: 2")
        element("sessionRow-alpha").rightClick()
        activate(element("archive-alpha"))
        wait(element("sessionRow-alpha"), "exists == false")
        notice("Archive calls: 1, Delete calls: 2")
    }
}
