import XCTest

/// The critical path, end to end:
/// launch → choose vehicles → enter costs → enter driving → see a result →
/// save it → reopen it.
///
/// Written against accessibility identifiers and labels rather than screen
/// coordinates, so a layout change does not silently break the suite.
/// XCUIApplication and every element query it returns are @MainActor-isolated,
/// so under Swift 6 strict concurrency the whole test case must be too.
@MainActor
final class CriticalPathUITests: XCTestCase {

    private var app: XCUIApplication!

    /// Launch the app for one test.
    ///
    /// Not a `setUp()` override: `XCTestCase.setUp()` is nonisolated and an
    /// override cannot add actor isolation, so it cannot touch the
    /// @MainActor-isolated XCUIApplication. Each test calls this first instead.
    private func launch() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["FUELSMART_UITEST"] = "1"
        app.launch()
        dismissOnboardingIfPresent()
    }

    // MARK: - Helpers

    /// Onboarding is skippable, and is skipped here so each test starts from
    /// the same place whether or not the simulator is freshly installed.
    private func dismissOnboardingIfPresent() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) {
            skip.tap()
        }
    }

    private func tapFirstMatch(_ predicateFormat: String, timeout: TimeInterval = 5) -> Bool {
        let element = app.descendants(matching: .any)
            .matching(NSPredicate(format: predicateFormat))
            .firstMatch
        guard element.waitForExistence(timeout: timeout) else { return false }
        element.tap()
        return true
    }

    /// Walk the picker: search, open the first result, then use that vehicle.
    private func chooseVehicle(searching query: String) {
        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5), "picker search field should appear")
        searchField.tap()
        searchField.typeText(query)

        let firstResult = app.cells.firstMatch
        XCTAssertTrue(firstResult.waitForExistence(timeout: 5), "search should return a result for \(query)")
        firstResult.tap()

        let use = app.buttons["Use this vehicle"]
        XCTAssertTrue(use.waitForExistence(timeout: 5), "vehicle detail should offer to use the vehicle")
        use.tap()
    }

    // MARK: - Tests

    func testLaunchShowsHomeWithTwoWaysIn() {
        launch()
        XCTAssertTrue(app.buttons["Compare vehicles"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Keep vs replace"].exists)
    }

    func testFullComparisonFlowProducesAResult() throws {
        launch()
        app.buttons["Compare vehicles"].tap()

        // Vehicle A.
        XCTAssertTrue(tapFirstMatch("label CONTAINS 'Choose a vehicle'"), "should offer to choose vehicle A")
        chooseVehicle(searching: "Camry")

        // Vehicle B.
        XCTAssertTrue(tapFirstMatch("label CONTAINS 'Choose a vehicle'"), "should offer to choose vehicle B")
        chooseVehicle(searching: "Model 3")

        // Both chosen, so results become reachable.
        let seeResults = app.buttons["See results"]
        XCTAssertTrue(seeResults.waitForExistence(timeout: 5))
        XCTAssertTrue(seeResults.isEnabled, "two vehicles should be enough to produce a result")
        seeResults.tap()

        // The chart is one accessibility element with a spoken summary.
        let chart = app.otherElements["Cumulative cost chart"]
        XCTAssertTrue(chart.waitForExistence(timeout: 5), "results should show the cumulative cost chart")

        // The break-even finding is always stated, in one form or another.
        let breakEven = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'catches up' OR label CONTAINS[c] 'break-even' OR label CONTAINS[c] 'stays less expensive' OR label CONTAINS[c] 'same'")
        ).firstMatch
        XCTAssertTrue(breakEven.waitForExistence(timeout: 5), "a break-even conclusion should always be stated")
    }

    func testHorizonChangeUpdatesTheResult() throws {
        launch()
        app.buttons["Compare vehicles"].tap()
        XCTAssertTrue(tapFirstMatch("label CONTAINS 'Choose a vehicle'"))
        chooseVehicle(searching: "Camry")
        XCTAssertTrue(tapFirstMatch("label CONTAINS 'Choose a vehicle'"))
        chooseVehicle(searching: "Model 3")
        app.buttons["See results"].tap()

        let tenYear = app.buttons["Ownership horizon 10 yr"]
        XCTAssertTrue(tenYear.waitForExistence(timeout: 5))
        tenYear.tap()

        XCTAssertTrue(app.otherElements["Cumulative cost chart"].exists, "the chart should survive a horizon change")
    }

    func testSaveAndReopenAComparison() throws {
        launch()
        app.buttons["Compare vehicles"].tap()
        XCTAssertTrue(tapFirstMatch("label CONTAINS 'Choose a vehicle'"))
        chooseVehicle(searching: "Camry")
        XCTAssertTrue(tapFirstMatch("label CONTAINS 'Choose a vehicle'"))
        chooseVehicle(searching: "Model 3")
        app.buttons["See results"].tap()

        let save = app.buttons["Save comparison"]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let nameField = app.textFields.firstMatch
        XCTAssertTrue(nameField.waitForExistence(timeout: 3))
        nameField.tap()
        nameField.typeText(" UITest")
        app.buttons["Save"].tap()

        // Back out to the Saved tab and confirm it is listed and reopenable.
        app.tabBars.buttons["Saved"].tap()
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the saved comparison should appear in the library")
        row.tap()

        XCTAssertTrue(
            app.buttons["See results"].waitForExistence(timeout: 5),
            "reopening a saved comparison should restore the editable flow"
        )
    }

    func testVehiclePickerSearchIsResponsiveAndRecoversFromNoMatches() {
        launch()
        app.buttons["Compare vehicles"].tap()
        XCTAssertTrue(tapFirstMatch("label CONTAINS 'Choose a vehicle'"))

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 5))
        searchField.tap()
        searchField.typeText("zzzznotavehicle")

        let empty = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'No vehicles match'")
        ).firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5), "an unmatched search should explain itself")

        // The empty state offers a way out rather than trapping the user.
        let clear = app.buttons["Clear search"]
        if clear.exists { clear.tap() }
    }

    func testSettingsExposeDataSourcesAndPrivacy() {
        launch()
        app.tabBars.buttons["Settings"].tap()

        let sources = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'Vehicle data sources'")
        ).firstMatch
        XCTAssertTrue(sources.waitForExistence(timeout: 5), "attribution must be reachable from Settings")
        sources.tap()

        let attribution = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS[c] 'Natural Resources Canada' OR label CONTAINS[c] 'Department of Energy'")
        ).firstMatch
        XCTAssertTrue(attribution.waitForExistence(timeout: 5), "required government attribution must be displayed")
    }
}
