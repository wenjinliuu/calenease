import XCTest

/// 关键流程：只守最核心的几条路径，每条都要在真实界面上点一遍。
/// 用 `--demo-data` 启动：App 加载示例班表，改动只在内存里，不读写用户数据。
///
/// 无障碍审计也在这里：流程走到哪一页，就在那一页跑一遍 `performAccessibilityAudit`，
/// 不为每个页面单独启动 App。失败信息以 “Accessibility audit” 开头，中央 CI 据此归为无障碍问题。
final class KeyFlowTests: XCTestCase {

    /// 目前审计的问题类型。对比度、动态字号、文字截断还有大量存量问题，清完后再加进来。
    private static let auditTypes: XCUIAccessibilityAuditType = [
        .hitRegion, .sufficientElementDescription, .elementDetection, .trait,
    ]

    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["--demo-data"]
        app.launch()
    }

    /// 四个主页面都能打开，每个页面各审计一遍。
    func testEveryMainTabOpens() {
        auditAccessibility(of: "日历")
        for tab in ["事项", "工时", "设置", "日历"] {
            let button = app.tabBars.buttons[tab]
            XCTAssertTrue(button.waitForExistence(timeout: 10), "找不到标签：\(tab)")
            button.tap()
            XCTAssertTrue(button.isSelected, "点了「\(tab)」没有切过去")
            if tab != "日历" { auditAccessibility(of: tab) }
        }
    }

    /// 月历左右滑动切月，再一键回到今天。
    func testMonthSwitcherMovesAndReturnsToToday() {
        let title = monthTitle()
        let start = title.label
        // 在今天那一行上横向拖：月历没有翻页按钮，只能滑
        let row = todayCell().frame.midY

        swipeMonth(from: 0.85, to: 0.15, atY: row)
        XCTAssertTrue(waitFor(title) { $0.label != start }, "向左滑后月份没变")
        let next = title.label
        swipeMonth(from: 0.15, to: 0.85, atY: row)
        swipeMonth(from: 0.15, to: 0.85, atY: row)
        XCTAssertTrue(waitFor(title) { $0.label != start && $0.label != next }, "向右滑后月份没变")

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
        auditAccessibility(of: "当天编辑")
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
        auditAccessibility(of: "新建日程")
        title.tap()
        title.typeText("CI 验收会")
        tapButton("保存")

        let created = app.buttons["编辑「CI 验收会」"]
        XCTAssertTrue(created.waitForExistence(timeout: 10), "保存后列表里没有这条日程")
    }

    // MARK: - 工具

    /// 在当前页面跑一遍无障碍审计。每个问题单独记一条失败，写明页面和元素，方便直接定位。
    /// runner 慢时审计偶尔超时（“Audit failed to complete in time”），这时重跑一次；再超时才算失败。
    private func auditAccessibility(of page: String) {
        // 一页的问题全部列出来再继续流程；审计完恢复“失败即停”
        let stopOnFailure = !continueAfterFailure
        continueAfterFailure = true
        defer { continueAfterFailure = !stopOnFailure }
        for attempt in 1...2 {
            // 先收集，审计完成后再报：超时重跑时不会把同一个问题记两遍
            var issues: [String] = []
            do {
                try app.performAccessibilityAudit(for: Self.auditTypes) { issue in
                    let element = issue.element.map { element in
                        let frame = element.frame
                        return "「\(element.label)」\(element.identifier) "
                            + "\(Int(frame.minX)),\(Int(frame.minY)) \(Int(frame.width))×\(Int(frame.height))"
                    } ?? "（没有元素）"
                    issues.append("\(issue.compactDescription) — \(element)")
                    return true
                }
                for issue in issues { XCTFail("Accessibility audit（\(page)）：\(issue)") }
                return
            } catch where attempt == 1 {
                continue
            } catch {
                XCTFail("Accessibility audit（\(page)）没有完成：\(error.localizedDescription)")
            }
        }
    }

    private func tapButton(_ label: String) {
        let button = app.buttons[label].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: 10), "找不到按钮：\(label)")
        button.tap()
    }

    /// 按屏幕宽度的比例横向拖一下；等标题动画走完再返回。
    private func swipeMonth(from startX: CGFloat, to endX: CGFloat, atY y: CGFloat) {
        let window = app.windows.firstMatch
        let origin = window.coordinate(withNormalizedOffset: .zero)
        let width = window.frame.width
        origin.withOffset(CGVector(dx: width * startX, dy: y))
            .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: width * endX, dy: y)))
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
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
