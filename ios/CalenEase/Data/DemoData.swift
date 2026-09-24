import Foundation

/// 截图与界面自查用的示例数据。
///
/// 只有带 `--demo-data` 启动参数时才会用到（CI 的截图流程），
/// 正常运行永远读用户自己的数据，也不会把示例写回磁盘。
enum DemoData {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("--demo-data")
    }

    /// 一份填好的班表：4白2休4夜2休，配几个职责标签，过去的班次标成已完成。
    static func document(today: Date = Date()) -> ScheduleDocument {
        var document = CareerPresets.apply(.manufacturing, to: .makeDefault())

        let parts = ScheduleCalendar.calendar.dateComponents([.year, .month], from: today)
        let year = parts.year ?? 2026
        let month = (parts.month ?? 1) - 1
        // 从上个月 1 号起排，日历往前往后翻都有内容
        let startYear = month == 0 ? year - 1 : year
        let startMonth = month == 0 ? 11 : month - 1
        let startDate = ScheduleCalendar.key(year: startYear, month: startMonth, day: 1)

        let template = document.cycleTemplates.first { $0.id == "tpl-four-two" }
            ?? document.cycleTemplates[0]
        let cycle = ActiveCycle(id: "cycle-demo",
                                name: template.name,
                                startDate: startDate,
                                shiftIds: template.shiftIds)
        document = CycleGenerator.replace(document, with: cycle, throughYear: year + 1)

        let todayKey = ScheduleCalendar.key(today)
        let tagIds = document.tags.prefix(2).map(\.id)
        for index in document.records.indices {
            let record = document.records[index]
            guard document.shift(record.shiftId)?.countsAsWork == true else { continue }
            if record.date < todayKey { document.records[index].completed = true }
            // 隔几天挂一个职责标签，让日历不至于太空
            if let tagId = tagIds.first, record.date.hasSuffix("3") || record.date.hasSuffix("8") {
                document.records[index].tagIds = [tagId]
            }
        }
        document.display.showTags = true
        return document
    }
}
