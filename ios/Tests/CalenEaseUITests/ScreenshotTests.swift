import XCTest

/// 走一遍三个主页面并截图。产物用于 App Store 素材，也用于界面自查。
/// 用 `--demo-data` 启动，App 会加载示例班表而不读写用户数据。
final class ScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--demo-data"]
        app.launch()
    }

    func testCaptureMainScreens() {
        capture("01-calendar")

        // 滚到底再截一张：验证内容没有被浮动标签栏压住
        scrollToBottom()
        capture("01b-calendar-bottom")
        tapTab("日历")

        tapTab("事项")
        capture("02a-agenda")

        tapTab("工时")
        capture("02-stats")
        scrollToBottom()
        capture("02b-stats-chart")

        tapTab("设置")
        capture("03-settings")

        tapTab("日历")
        // 打开循环排班，展示模板与序列
        let generator = app.buttons["循环排班"]
        if generator.waitForExistence(timeout: 5) {
            generator.tap()
            capture("04-cycle-generator")
            dismissSheet()
        }

        // 先回到今天，再用当天的可访问性标签定位日期。
        // 月历会保留相邻月份的离屏元素，按索引取日期可能误点不可见的格子。
        let today = app.buttons["回到今天"]
        XCTAssertTrue(today.waitForExistence(timeout: 5))
        today.tap()
        let day = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "day-", "今天"))
            .firstMatch
        XCTAssertTrue(day.waitForExistence(timeout: 10), "日历上没有找到今天")
        day.tap()
        Thread.sleep(forTimeInterval: 1.2)
        capture("05-day-editor")
        let events = app.buttons["日程"]
        if events.exists {
            events.tap()
            Thread.sleep(forTimeInterval: 1.0)
            capture("06-day-events")
        }
    }

    // MARK: - 工具

    private func tapTab(_ label: String) {
        let tab = app.tabBars.buttons[label]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "找不到标签：\(label)")
        tab.tap()
        // 等一帧，避免截到转场中间态
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func scrollToBottom() {
        let scroll = app.scrollViews.firstMatch
        guard scroll.waitForExistence(timeout: 5) else { return }
        for _ in 0..<4 { scroll.swipeUp(velocity: .fast) }
        Thread.sleep(forTimeInterval: 1.2)
    }

    private func dismissSheet() {
        let cancel = app.buttons["取消"]
        if cancel.exists { cancel.tap() }
        Thread.sleep(forTimeInterval: 0.8)
    }

    private func capture(_ name: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
