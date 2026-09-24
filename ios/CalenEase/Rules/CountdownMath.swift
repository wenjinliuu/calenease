import Foundation

/// 倒计时卡片上显示的东西。
struct CountdownStatus: Hashable, Sendable {
    /// 大数字：天数。
    let days: Int
    /// 数字前面那两个字：「还有」「已经」「已过」「就是今天」。
    let caption: String
    /// 这一次对应的日期（每年重复的是下一次的日期）。
    let targetDate: String
    /// 正数日的「1 年 3 个月 5 天」，其余为 nil。
    let breakdown: String?
    let isToday: Bool
}

enum CountdownMath {

    static func status(of countdown: Countdown, today: String) -> CountdownStatus? {
        guard let now = DayNumber.of(today), let origin = DayNumber.of(countdown.date) else { return nil }
        switch countdown.kind {
        case .countdown:
            let target = countdown.repeatsYearly ? nextAnniversary(of: origin, onOrAfter: now) : origin
            let diff = target - now
            let caption = diff > 0 ? "还有" : diff == 0 ? "就是今天" : "已过"
            return CountdownStatus(days: abs(diff), caption: caption, targetDate: DayNumber.key(target),
                                   breakdown: nil, isToday: diff == 0)
        case .countUp:
            let diff = now - origin
            if diff < 0 {
                return CountdownStatus(days: -diff, caption: "还有", targetDate: countdown.date,
                                       breakdown: nil, isToday: false)
            }
            return CountdownStatus(days: diff, caption: "已经", targetDate: countdown.date,
                                   breakdown: breakdown(from: origin, to: now), isToday: diff == 0)
        }
    }

    /// 从 `origin` 那天起每年的同月同日里，不早于 `day` 的第一个。2 月 29 日在平年落到 2 月 28 日。
    static func nextAnniversary(of origin: Int, onOrAfter day: Int) -> Int {
        let anchor = DayNumber.civil(origin)
        let current = DayNumber.civil(day)
        for year in current.year...(current.year + 1) {
            let dayOfMonth = anchor.month == 2 && anchor.day == 29 && !DayNumber.isLeapYear(year) ? 28 : anchor.day
            let candidate = DayNumber.from(year: year, month: anchor.month, day: dayOfMonth)
            if candidate >= day { return candidate }
        }
        return day
    }

    /// 「1 年 3 个月 5 天」。整年、整月按日历算，不按 365 / 30 天折算。
    ///
    /// 先数整月：从起始日往后加 N 个月（没有那一天的月份落到月底）不超过结束日的最大 N，
    /// 剩下的零头就是天数。1 月 31 日到 3 月 1 日是「1 个月 1 天」。
    static func breakdown(from start: Int, to end: Int) -> String? {
        guard end >= start else { return nil }
        let from = DayNumber.civil(start), to = DayNumber.civil(end)
        var months = (to.year - from.year) * 12 + (to.month - from.month)
        if to.day < from.day { months -= 1 }
        months = max(0, months)
        let anchor = adding(months: months, to: from)
        let days = end - anchor
        var parts: [String] = []
        if months >= 12 { parts.append("\(months / 12) 年") }
        if months % 12 > 0 { parts.append("\(months % 12) 个月") }
        if days > 0 || parts.isEmpty { parts.append("\(days) 天") }
        return parts.joined(separator: " ")
    }

    private static func adding(months: Int, to date: (year: Int, month: Int, day: Int)) -> Int {
        let total = date.year * 12 + (date.month - 1) + months
        let year = total / 12, month = total % 12 + 1
        return DayNumber.from(year: year, month: month, day: min(date.day, daysInMonth(year: year, month: month)))
    }

    static func daysInMonth(year: Int, month: Int) -> Int {
        let next = month == 12 ? DayNumber.from(year: year + 1, month: 1, day: 1)
                               : DayNumber.from(year: year, month: month + 1, day: 1)
        return next - DayNumber.from(year: year, month: month, day: 1)
    }

    /// 首页排列：置顶的在前；其余按离今天多近排，正数日排在倒数日后面。
    static func sorted(_ countdowns: [Countdown], today: String) -> [(Countdown, CountdownStatus)] {
        countdowns.compactMap { item in status(of: item, today: today).map { (item, $0) } }
            .sorted { lhs, rhs in
                if lhs.0.pinned != rhs.0.pinned { return lhs.0.pinned }
                let lhsUp = lhs.0.kind == .countUp, rhsUp = rhs.0.kind == .countUp
                if lhsUp != rhsUp { return !lhsUp }
                let lhsPast = lhs.1.caption == "已过", rhsPast = rhs.1.caption == "已过"
                if lhsPast != rhsPast { return !lhsPast }
                return lhs.1.days < rhs.1.days
            }
    }
}
