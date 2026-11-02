import XCTest

/// Drives the app with its sample content (`-ui-testing`: the in-memory test repositories), so nothing reaches a server.
final class FolioUITests: XCTestCase {
    private var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing"]
        app.launch()
    }
    
    // MARK: - Tests
    
    @MainActor
    func testEachTabShowsItsContent() throws {
        XCTAssertTrue(app.staticTexts["Sample Project"].waitForExistence(timeout: 5))
        
        tab("Posts").tap()
        XCTAssertTrue(app.staticTexts["Sample Post"].waitForExistence(timeout: 5))
        
        tab("Apps").tap()
        XCTAssertTrue(app.staticTexts["Sample App"].waitForExistence(timeout: 5))
    }
    
    @MainActor
    func testEditingAPostPublishesIt() throws {
        tab("Posts").tap()
        app.staticTexts["Sample Post"].firstMatch.tap()
        
        let title = app.textFields["Title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeKey("a", modifierFlags: .command)
        title.typeText("Renamed Post")
        app.buttons["Publish"].firstMatch.tap()
        
        goBack()
        XCTAssertTrue(app.staticTexts["Renamed Post"].waitForExistence(timeout: 5))
    }
    
    @MainActor
    func testDeletingAPostAsksFirst() throws {
        tab("Posts").tap()
        let row = app.staticTexts["Sample Post"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        #if os(macOS)
        row.rightClick()
        #else
        row.press(forDuration: 1)
        #endif
        app.buttons["Delete…"].firstMatch.tap()
        
        let confirm = app.buttons["Delete Post"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5), "deleting asks for confirmation")
        XCTAssertTrue(row.exists, "nothing is deleted before confirming")
        confirm.tap()
        
        XCTAssertTrue(app.staticTexts["No Posts"].waitForExistence(timeout: 5))
    }
    
    // MARK: - Helpers
    
    /// A tab of the sidebar-adaptable tab view: a tab bar button on iPhone, a sidebar row on macOS.
    private func tab(_ title: String) -> XCUIElement {
        #if os(macOS)
        app.outlines.staticTexts[title].firstMatch
        #else
        app.tabBars.buttons[title].firstMatch
        #endif
    }
    
    private func goBack() {
        #if os(macOS)
        app.typeKey("[", modifierFlags: .command)
        #else
        app.navigationBars.buttons.element(boundBy: 0).tap()
        #endif
    }
}
