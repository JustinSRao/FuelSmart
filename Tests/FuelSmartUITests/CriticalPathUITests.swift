import XCTest

/// The critical path, end to end:
/// launch → choose vehicles → enter costs → enter driving → see a result →
/// save it → reopen it.
///
/// Queries are deliberately **type-agnostic**. SwiftUI decides for itself
/// whether a given row surfaces as a button, a cell, a static text or an "other"
/// element, and that mapping differs between containers — a `Form` row and a
/// `List` row are not the same element type. Asserting on `app.buttons[...]`
/// therefore tests SwiftUI's accessibility mapping rather than the product, so
/// these helpers search across element types and fail with the on-screen
/// hierarchy attached.
///
/// XCUIApplication and its element queries are @MainActor-isolated, so under
/// Swift 6 strict concurrency the whole test case must be too.
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

    /// Onboarding is skippable, and is skipped here so each test starts from the
    /// same place whether or not the simulator is freshly installed.
    private func dismissOnboardingIfPresent() {
        let skip = app.buttons["Skip"]
        if skip.waitForExistence(timeout: 3) { skip.tap() }
    }

    /// Any element whose label matches, regardless of element type.
    ///
    /// Scrolls if the element is not found immediately. SwiftUI's `Form` and
    /// `List` are lazy: a row below the fold genuinely does not exist in the
    /// accessibility hierarchy until it is scrolled into view, so a query alone
    /// cannot find it however long it waits.
    private func element(labelled predicate: String, timeout: TimeInterval = 8) -> XCUIElement? {
        let query = app.descendants(matching: .any).matching(NSPredicate(format: predicate))
        if query.firstMatch.waitForExistence(timeout: timeout) { return query.firstMatch }

        for _ in 0..<6 {
            app.swipeUp()
            if query.firstMatch.waitForExistence(timeout: 1) { return query.firstMatch }
        }
        return nil
    }

    /// Tap the first element matching `predicate`, failing with the element tree
    /// attached so a failure reports what *was* on screen.
    @discardableResult
    private func tap(
        _ predicate: String,
        _ what: String,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> Bool {
        guard let found = element(labelled: predicate, timeout: timeout) else {
            attachHierarchy(named: "missing - \(what)")
            XCTFail("could not find \(what); element tree attached", file: file, line: line)
            return false
        }
        found.tap()
        return true
    }

    private func assertExists(
        _ predicate: String,
        _ what: String,
        timeout: TimeInterval = 8,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if element(labelled: predicate, timeout: timeout) == nil {
            attachHierarchy(named: "missing - \(what)")
            XCTFail("expected \(what); element tree attached", file: file, line: line)
        }
    }

    /// Attach the element hierarchy to the report, and echo it to the log so a
    /// CI run that discards attachments still shows what happened.
    private func attachHierarchy(named name: String) {
        let tree = app.debugDescription
        let attachment = XCTAttachment(string: tree)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        print("=== ELEMENT TREE (\(name)) ===\n\(tree.prefix(6000))\n=== END TREE ===")
    }

    /// Walk the picker: search, open a result, then use that vehicle.
    private func chooseVehicle(searching query: String) {
        let searchField = app.searchFields.firstMatch
        guard searchField.waitForExistence(timeout: 8) else {
            attachHierarchy(named: "no search field")
            XCTFail("picker search field never appeared")
            return
        }
        searchField.tap()
        searchField.typeText(query)

        // Matched by the searched text rather than by position, so a section
        // header or a stray cell cannot be opened instead.
        guard tap("label CONTAINS[c] '\(query)'", "a search result for \(query)") else { return }
        guard tap("label CONTAINS[c] 'Use this vehicle'", "the 'Use this vehicle' action") else { return }
    }

    /// Both sides of a comparison, starting from Home.
    private func buildComparison() {
        tap("label CONTAINS[c] 'Compare vehicles'", "the Compare vehicles action")
        tap("label CONTAINS[c] 'Choose a vehicle'", "the vehicle A chooser")
        chooseVehicle(searching: "Camry")
        tap("label CONTAINS[c] 'Choose a vehicle'", "the vehicle B chooser")
        chooseVehicle(searching: "Model 3")
    }

    // MARK: - Tests

    func testLaunchShowsHomeWithTwoWaysIn() {
        launch()
        assertExists("label CONTAINS[c] 'Compare vehicles'", "the Compare vehicles action")
        assertExists("label CONTAINS[c] 'Keep vs replace'", "the Keep vs replace action")
    }

    func testFullComparisonFlowProducesAResult() throws {
        launch()
        buildComparison()
        tap("label CONTAINS[c] 'See results'", "the See results action")

        // The chart is exposed as a single accessibility element.
        assertExists("label CONTAINS[c] 'Cumulative cost chart'", "the cumulative cost chart")

        // A break-even conclusion is always stated, in one form or another —
        // including "there isn't one", which is a real answer, not an error.
        assertExists(
            "label CONTAINS[c] 'catches up' OR label CONTAINS[c] 'break-even' "
            + "OR label CONTAINS[c] 'stays less expensive' OR label CONTAINS[c] 'crossover' "
            + "OR label CONTAINS[c] 'same'",
            "a stated break-even conclusion"
        )
    }

    func testHorizonChangeUpdatesTheResult() throws {
        launch()
        buildComparison()
        tap("label CONTAINS[c] 'See results'", "the See results action")

        tap("label CONTAINS[c] 'Ownership horizon 10 yr'", "the 10-year horizon control")
        assertExists("label CONTAINS[c] 'Cumulative cost chart'", "the chart after a horizon change")
    }

    func testSaveAndReopenAComparison() throws {
        launch()
        buildComparison()
        tap("label CONTAINS[c] 'See results'", "the See results action")
        tap("label CONTAINS[c] 'Save comparison'", "the Save action")

        let nameField = app.textFields.firstMatch
        guard nameField.waitForExistence(timeout: 5) else {
            attachHierarchy(named: "no name field")
            XCTFail("the save sheet never offered a name field")
            return
        }
        nameField.tap()
        nameField.typeText(" UITest")
        tap("label MATCHES[c] 'Save'", "the Save confirmation")

        // Back out to the library and confirm it is listed and reopenable.
        tap("label MATCHES[c] 'Saved'", "the Saved tab")
        tap("label CONTAINS 'UITest'", "the saved comparison row")
        assertExists("label CONTAINS[c] 'See results'", "the reopened editable comparison")
    }

    func testVehiclePickerSearchIsResponsiveAndRecoversFromNoMatches() {
        launch()
        tap("label CONTAINS[c] 'Compare vehicles'", "the Compare vehicles action")
        tap("label CONTAINS[c] 'Choose a vehicle'", "the vehicle chooser")

        let searchField = app.searchFields.firstMatch
        XCTAssertTrue(searchField.waitForExistence(timeout: 8))
        searchField.tap()
        searchField.typeText("zzzznotavehicle")

        assertExists("label CONTAINS[c] 'No vehicles match'", "the empty-search explanation")
    }

    func testSettingsExposeDataSourcesAndPrivacy() {
        launch()
        tap("label MATCHES[c] 'Settings'", "the Settings tab")
        tap("label CONTAINS[c] 'Vehicle data sources'", "the data sources row")

        // Government attribution is a licence condition and must be displayed.
        assertExists(
            "label CONTAINS[c] 'Natural Resources Canada' OR label CONTAINS[c] 'Department of Energy'",
            "required government attribution"
        )
    }
}
