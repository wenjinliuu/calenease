import XCTest

/// 关键流程：只守最核心的几条路径，每条都要在真实界面上点一遍。
/// 用 `--demo-data` 启动：App 加载示例班表，改动只在内存里，不读写用户数据。
final class KeyFlowTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--demo-data"]
        app.launch()
    }

    /// 四个主页面都能打开。
    func testEveryMainTabOpens() {
        for tab in ["事项", "工时", "设置", "日历"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "找不到标签：\(tab)")
            button.tap()
            XCTAssertTrue(button.isSelected, "点了「\(tab)」没有切过去")
        }
    }

    /// 左右切月，再一键回到今天。
    func testMonthSwitcherMovesAndReturnsToToday() {
        let title = monthTitle()
        let start = title.label

        tapButton("下个月")
        XCTAssertTrue(waitFor(title) { $0.label != start }, "点「下个月」后月份没变")
        tapButton("上个月")
        tapButton("上个月")
        XCTAssertTrue(waitFor(title) { $0.label != start }, "点「上个月」后月份没变")

        tapButton("回到今天")
        XCTAssertTrue(waitFor(title) { $0.label == start }, "「回到今天」没有回到本月")
    }

    /// 点今天打开编辑器，改成请假，格子跟着变。
    func testEditingTodayChangesItsShift() {
        tapButton("回到今天")
        let cell = todayCell()
        cell.tap()

        let leave = app.buttons.containing(NSPredicate(format: "label CONTAINS %@", "请假")).firstMatch
        XCTAssertTrue(leave.waitForExistence(timeout: 10), "编辑器里没有「请假」")
        leave.tap()
        tapButton("完成")

        XCTAssertTrue(waitFor(todayCell()) { $0.label.contains("请假") }, "保存后今天没有显示请假")
    }

    /// 在事项页新建一条日程，保存后出现在列表里。
    func testCreatingAnEventInAgenda() {
        app.tabBars.buttons["事项"].tap()
        tapButton("新建日程")

        let title = app.textFields["标题"]
        XCTAssertTrue(title.waitForExistence(timeout: 10), "新建日程没有标题输入框")
        title.tap()
        title.typeText("CI 验收会")
        tapButton("保存")

        let created = app.buttons["编辑「CI 验收会」"]
        XCTAssertTrue(created.waitForExistence(timeout: 10), "保存后列表里没有这条日程")
    }

    // MARK: - 工具

    private func tapButton(_ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "找不到按钮：\(label)")
        button.tap()
    }

    /// 月份标题的朗读文字是「2026年9月」这样的格式。
    private func monthTitle() -> XCUIElement {
        let title = app.buttons.matching(NSPredicate(format: "label MATCHES %@", "^\\d{4}年\\d{1,2}月$")).firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 10), "找不到月份标题")
        return title
    }

    /// 月历会保留相邻月份的离屏格子，按「今天」这个朗读文字找，不按位置取。
    private func todayCell() -> XCUIElement {
        let cell = app.buttons
            .matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label CONTAINS %@", "day-", "今天"))
            .firstMatch
        XCTAssertTrue(cell.waitForExistence(timeout: 10), "日历上没有找到今天")
        return cell
    }

    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 5,
                         _ condition: @escaping (XCUIElement) -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && condition(element) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        return element.exists && condition(element)
    }
}
