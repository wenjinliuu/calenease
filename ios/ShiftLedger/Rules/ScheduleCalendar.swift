import Foundation

/// 日期在整个 App 里统一用 "yyyy-MM-dd" 字符串表示，
/// 和 web 版的 `dateKey` 一致，备份文件、循环推算、SwiftUI 选择态都用它。
enum ScheduleCalendar {
    /// 排班用的日历：公历 + 当前时区，周一为一周之始。
    ///
    /// 只建一次。原来是计算属性，每取一次就新建一个 `Calendar`——日历一格要判节假日、
    /// 推日期好几次，翻一个月就是几百次，滑动时全耗在这上面。
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .autoupdatingCurrent
        calendar.firstWeekday = 2
        return calendar
    }()

    static func key(_ date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return key(year: parts.year ?? 0, month: (parts.month ?? 1) - 1, day: parts.day ?? 1)
    }

    /// `month` 是零基，和 web 版 `Date#getMonth()` 保持一致。
    static func key(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month + 1, day)
    }

    static func monthKey(year: Int, month: Int) -> String {
        String(format: "%04d-%02d", year, month + 1)
    }

    static func date(from key: String) -> Date? {
        guard let parts = components(from: key) else { return nil }
        return calendar.date(from: DateComponents(year: parts.year, month: parts.month + 1, day: parts.day))
    }

    static func components(from key: String) -> (year: Int, month: Int, day: Int)? {
        let pieces = key.split(separator: "-")
        guard pieces.count == 3,
              let year = Int(pieces[0]), let month = Int(pieces[1]), let day = Int(pieces[2])
        else { return nil }
        return (year, month - 1, day)
    }

    static var todayKey: String { key(Date()) }

    static func adding(days: Int, to key: String) -> String {
        guard let date = date(from: key),
              let moved = calendar.date(byAdding: .day, value: days, to: date)
        else { return key }
        return Self.key(moved)
    }

    /// 两个日期相差的天数（`a - b`）。
    static func dayDifference(_ a: String, _ b: String) -> Int {
        guard let left = date(from: a), let right = date(from: b) else { return 0 }
        return calendar.dateComponents([.day], from: calendar.startOfDay(for: right),
                                       to: calendar.startOfDay(for: left)).day ?? 0
    }

    /// 闭区间的日期序列，顺序总是从早到晚。
    static func range(_ first: String, _ second: String) -> [String] {
        let start = min(first, second)
        let end = max(first, second)
        var result: [String] = []
        var cursor = start
        while cursor <= end {
            result.append(cursor)
            let next = adding(days: 1, to: cursor)
            if next == cursor { break }
            cursor = next
        }
        return result
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first)
        else { return 30 }
        return range.count
    }

    /// 该月 1 号前面要空出的格子数（周一开头）。
    static func leadingBlanks(year: Int, month: Int) -> Int {
        guard let first = calendar.date(from: DateComponents(year: year, month: month + 1, day: 1)) else { return 0 }
        // weekday: 周日=1 … 周六=7，转成周一=0 … 周日=6
        return (calendar.component(.weekday, from: first) + 5) % 7
    }

    /// 周一=0 … 周日=6。
    static func weekdayIndex(_ key: String) -> Int {
        guard let date = date(from: key) else { return 0 }
        return (calendar.component(.weekday, from: date) + 5) % 7
    }

    static func isWeekend(_ key: String) -> Bool { weekdayIndex(key) >= 5 }

    /// 所在周的周一，用于按周汇总加班。
    static func startOfWeek(_ key: String) -> String {
        adding(days: -weekdayIndex(key), to: key)
    }

    static let weekdaySymbols = ["一", "二", "三", "四", "五", "六", "日"]
}

/// 一个月的定位信息。
struct ReportingMonth: Hashable, Sendable, Identifiable {
    var year: Int
    /// 零基。
    var month: Int

    var id: String { key }
    var key: String { ScheduleCalendar.monthKey(year: year, month: month) }
    var label: String { "\(month + 1)月" }
    var fullLabel: String { "\(year)年\(month + 1)月" }
}

/// 12 个月的年度周期。综合计算工时可以把年度起点设在任意月份。
struct AnnualCycle: Hashable, Sendable {
    var months: [ReportingMonth]

    var startYear: Int { months.first?.year ?? 0 }
    var startMonth: Int { months.first?.month ?? 0 }
    var endYear: Int { months.last?.year ?? 0 }
    var endMonth: Int { months.last?.month ?? 0 }

    var startDate: String { ScheduleCalendar.key(year: startYear, month: startMonth, day: 1) }

    var endDate: String {
        ScheduleCalendar.key(year: endYear,
                             month: endMonth,
                             day: ScheduleCalendar.daysInMonth(year: endYear, month: endMonth))
    }

    var label: String {
        startYear == endYear
            ? "\(startYear)年\(startMonth + 1)月–\(endMonth + 1)月"
            : "\(startYear)年\(startMonth + 1)月–\(endYear)年\(endMonth + 1)月"
    }

    /// 包含指定月份的年度周期。`annualStartMonth` 为一基。
    static func containing(year: Int, month: Int, annualStartMonth: Int = 1) -> AnnualCycle {
        let safeStart = (1...12).contains(annualStartMonth) ? annualStartMonth : 1
        let startMonth = safeStart - 1
        let startYear = month >= startMonth ? year : year - 1
        let months = (0..<12).map { offset -> ReportingMonth in
            let absolute = startMonth + offset
            return ReportingMonth(year: startYear + absolute / 12, month: absolute % 12)
        }
        return AnnualCycle(months: months)
    }
}
