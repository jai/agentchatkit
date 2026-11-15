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
        activate(app.switches[label])
        #endif
    }

    func wait(_ element: XCUIElement, _ predicate: String, timeout: TimeInterval = 6) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }

    func notice(_ text: String) { wait(element("fixture-notice"), "label == '\(text)'") }

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
