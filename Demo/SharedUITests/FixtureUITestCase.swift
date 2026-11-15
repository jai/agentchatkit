import XCTest

@MainActor
class FixtureUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUp() { continueAfterFailure = false }

    func launch(_ fixture: String, appearance: String = "light", customIDs: Bool = true,
                legacyTypography: Bool = false) {
        if app != nil { app.terminate() }
        app = XCUIApplication()
        app.launchArguments = ["-DemoFixture", fixture, "-DemoTheme", "paper", "-DemoAppearance", appearance,
                               "-DemoCustomIDs", customIDs ? "YES" : "NO",
                               "-DemoLegacyTypography", legacyTypography ? "YES" : "NO"]
        app.launch()
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    }

    func element(_ id: String) -> XCUIElement { app.descendants(matching: .any)[id].firstMatch }

    func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    func toggle(_ label: String) {
        #if os(macOS)
        activate(app.checkBoxes[label])
        #else
        app.flipSwitch(label)
        #endif
    }

    func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 6) {
        #if os(macOS)
        // AppKit StaticText exposes its visible words as value; controls still use label.
        let textPredicate = predicate.contains("label")
            ? "(\(predicate)) OR (\(predicate.replacingOccurrences(of: "label", with: "value")))" : predicate
        #else
        let textPredicate = predicate
        #endif
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: textPredicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    /// Any element with the notice's ID showing `text`: after a context menu or dialog closes, iOS 26 can keep a stale
    /// copy of the screen, whose notice is found first.
    func notice(_ text: String) {
        let showing = app.descendants(matching: .any).matching(NSPredicate(
            format: "identifier == 'fixture-notice' AND (label == %@ OR value == %@)", text, text)).firstMatch
        XCTAssertTrue(showing.waitForExistence(timeout: 6), "fixture-notice never showed \(text)")
    }

    func keep(_ name: String) throws {
        #if os(macOS)
        let platform = "macos"
        #else
        let platform = "ios"
        #endif
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "\(platform)-\(name)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let folder = ProcessInfo.processInfo.environment["CHATDEMO_SCREENSHOTS"] {
            let url = URL(fileURLWithPath: folder, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try screenshot.pngRepresentation.write(to: url.appending(path: "\(platform)-\(name).png"))
        }
    }
}

#if os(iOS)
extension XCUIApplication {
    /// On iOS 26 a tap in the middle of a full-width Toggle lands on its label, which does not flip it.
    func flipSwitch(_ label: String, file: StaticString = #filePath, line: UInt = #line) {
        let toggle = switches[label]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), file: file, line: line)
        let before = toggle.value as? String ?? ""
        let knob = toggle.switches.firstMatch
        if knob.exists {
            knob.tap()
        } else {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        }
        let flipped = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value != %@", before), object: toggle)
        XCTAssertEqual(XCTWaiter.wait(for: [flipped], timeout: 3), .completed, file: file, line: line)
    }

    /// iOS 26 shows a row's confirmation dialog without a Cancel button; a tap outside it is the cancel.
    func cancelConfirmation(_ cancelID: String = "Cancel") {
        let cancel = buttons[cancelID].firstMatch
        if cancel.waitForExistence(timeout: 2) {
            cancel.tap()
            return
        }
        // Tap the dimmed screen outside the dialog, on whichever side has room; the navigation bar does not dismiss it.
        let dialog = sheets.firstMatch
        let screen = windows.firstMatch.frame
        let frame = dialog.exists ? dialog.frame : CGRect(x: 0, y: screen.midY, width: screen.width, height: 0)
        let height = max(screen.height, 1)
        let y = frame.minY > 200 ? (frame.minY - 60) / height : (frame.maxY + 60) / height
        coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: min(max(y, 0.15), 0.95))).tap()
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dialog)
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 3), .completed, "the confirmation dialog stayed open")
    }
}
#endif
