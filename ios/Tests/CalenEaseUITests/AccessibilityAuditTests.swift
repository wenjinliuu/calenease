import XCTest

/// 无障碍审计：在每个主页面跑一遍系统的 `performAccessibilityAudit()`。
/// 类名带 Accessibility，中央 CI 会把这里的失败单独列为「无障碍问题」，目前只警告不阻断；
/// 问题清干净后把入口文件的 accessibility_audit 改成 fail。
final class AccessibilityAuditTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["--demo-data"]
        app.launch()
    }

    func testAccessibilityAuditOfMainScreens() throws {
        for tab in ["日历", "事项", "工时", "设置"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "找不到标签：\(tab)")
            button.tap()
            try app.performAccessibilityAudit()
        }
    }
}
