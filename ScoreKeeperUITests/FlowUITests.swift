import XCTest

final class FlowUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        executionTimeAllowance = 900
    }

    func testAAAWarmUpSimulator() {
        XCTExpectFailure("云端模拟器首次启动可能超时", strict: false)
        launch()
        app.terminate()
    }

    @discardableResult private func launch(_ arguments: [String] = [], language: String = "en", reset: Bool = true) -> XCUIApplication {
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-AppleLanguages", "(\(language))",
                               "-AppleLocale", language == "en" ? "en_US" : language.replacingOccurrences(of: "-", with: "_")]
        if reset { app.launchArguments.append("-reset") }
        app.launchArguments += arguments
        app.launch()
        return app
    }

    @discardableResult private func tap(_ id: String, timeout: TimeInterval = 8, file: StaticString = #filePath, line: UInt = #line) -> XCUIElement {
        let element = app.descendants(matching: .any).matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "没找到 \(id)", file: file, line: line)
        for _ in 0..<3 where !element.isHittable { app.swipeUp() }
        element.tap()
        return element
    }

    private func label(_ id: String) -> String {
        let element = app.staticTexts.matching(identifier: id).firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 8), "没找到 \(id)")
        return element.label
    }

    func testStartRecordUndoSettleAndHistory() {
        launch()
        tap("table.new")
        tap("new.start")
        XCTAssertTrue(app.staticTexts["table.name"].waitForExistence(timeout: 8))

        tap("round.record")
        tap("record.winner.0")
        tap("record.quick.24")
        tap("record.save")
        XCTAssertEqual(label("total.0"), "+24")
        XCTAssertEqual(label("total.3"), "-8")

        tap("round.record")
        tap("record.winner.1")
        tap("record.quick.48")
        tap("record.save")
        XCTAssertEqual(label("total.0"), "+40")

        tap("open.menu")
        tap("menu.undo")
        tap("undo.confirm")
        XCTAssertEqual(label("total.0"), "+24")

        tap("settle.open")
        XCTAssertTrue(app.staticTexts["settle.amount.0"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["share.image"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.buttons["share.link"].exists)
        tap("settle.close")
        XCTAssertTrue(app.buttons["table.new"].waitForExistence(timeout: 8))

        tap("open.history")
        XCTAssertTrue(app.buttons["history.row.0"].waitForExistence(timeout: 8))
    }

    func testEachModeAutofillsLastPlayer() {
        launch()
        tap("table.new")
        tap("new.start")
        tap("round.record")
        app.segmentedControls["record.mode"].buttons.element(boundBy: 1).tap()
        for (i, v) in ["30", "-10", "-5"].enumerated() {
            tap("record.entry.\(i)")
            app.typeText(v)
        }
        tap("record.save")
        XCTAssertEqual(label("total.0"), "+30")
        XCTAssertEqual(label("total.3"), "-15")
    }

    func testDataSurvivesRelaunch() {
        launch()
        tap("table.new")
        tap("new.start")
        tap("round.record")
        tap("record.winner.2")
        tap("record.quick.16")
        tap("record.save")
        app.terminate()
        launch(reset: false)
        XCTAssertEqual(label("total.0"), "+16")
    }

    func testStoreScreenshots() {
        for language in ["en", "ja", "zh-Hans", "zh-Hant"] {
            for (file, scene) in [("01-table", ""), ("02-record", "record"), ("03-settle", "settle"),
                                  ("04-history", "history"), ("05-new", "newTable")] {
                launch(["-demo"] + (scene.isEmpty ? [] : ["-scene", scene]), language: language)
                switch scene {
                case "": XCTAssertTrue(app.staticTexts["total.0"].waitForExistence(timeout: 8))
                case "record":
                    tap("record.winner.1")
                    tap("record.quick.24")
                case "settle": XCTAssertTrue(app.staticTexts["settle.amount.0"].waitForExistence(timeout: 8))
                case "history": XCTAssertTrue(app.buttons["history.row.0"].waitForExistence(timeout: 8))
                default: XCTAssertTrue(app.buttons["new.start"].waitForExistence(timeout: 8))
                }
                capture("store-\(language)-\(file)")
                app.terminate()
            }
        }
    }

    func testPaidScreenshot() {
        launch(["-scene", "paywall"], language: "zh-Hans")
        XCTAssertTrue(app.buttons["paywall.buy"].waitForExistence(timeout: 8))
        capture("paid-01-paywall")
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
