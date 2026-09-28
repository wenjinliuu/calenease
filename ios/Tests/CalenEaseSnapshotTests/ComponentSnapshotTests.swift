import SnapshotTesting
import SwiftUI
import XCTest
@testable import CalenEase

/// 界面组件的快照：固定日期 + 示例数据，逐像素对比 `__Snapshots__` 里的参考图。
///
/// 参考图只在 CI 上录制（手动运行 Build & Test 并勾选 record_snapshots），本地录的图和 CI 的
/// 模拟器、系统版本不一致，比出来全是误报。有意改了界面就重新录制，并在提交里写明改了哪些组件。
@MainActor
final class ComponentSnapshotTests: XCTestCase {

    /// 2026-09-15 周二。示例数据从上个月 1 号起按 4 白 2 休 4 夜 2 休排班，过去的班次标成已完成。
    private let today = ScheduleCalendar.calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 12))!

    private lazy var document = DemoData.document(today: today)

    func testMonthGridLight() {
        assertComponent(monthGrid, style: .light)
    }

    func testMonthGridDark() {
        assertComponent(monthGrid, style: .dark)
    }

    func testCycleStrip() {
        let template = document.cycleTemplates.first { $0.id == "tpl-four-two" } ?? document.cycleTemplates[0]
        assertComponent(CycleStrip(shiftIds: template.shiftIds, document: document, showsIndex: true), style: .light)
    }

    func testShiftPickerGrid() {
        assertComponent(ShiftPickerGrid(shifts: document.orderedShifts, selection: document.orderedShifts[0].id, onSelect: { _ in }),
                        style: .light)
    }

    // MARK: - 工具

    private var monthGrid: some View {
        // month 是零基：8 = 九月
        CalendarMonthGrid(year: 2026, month: 8, document: document,
                          todayKey: ScheduleCalendar.key(today), onSelect: { _ in })
    }

    /// iPhone 17 Pro 的宽度，高度按内容。
    private func assertComponent(_ view: some View, style: UIUserInterfaceStyle,
                                 file: StaticString = #filePath, testName: String = #function, line: UInt = #line) {
        let framed = view
            .padding(16)
            .frame(width: 402)
            .background(Color(.systemBackground))
            .environment(\.colorScheme, style == .dark ? .dark : .light)
        assertSnapshot(of: framed,
                       as: .image(precision: 0.99, perceptualPrecision: 0.98, layout: .sizeThatFits,
                                  traits: UITraitCollection(userInterfaceStyle: style)),
                       file: file, testName: testName, line: line)
    }
}
