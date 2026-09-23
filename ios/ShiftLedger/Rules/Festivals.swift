import Foundation

/// 节日。只在节日当天有，不管放几天假——国庆只在 10 月 1 日写「国庆」。
struct Festival: Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// 八个法定节日：元旦、除夕、春节、清明、劳动节、端午、中秋、国庆。红色。
        case statutory
        /// 传统节日：元宵、七夕、中元、重阳、腊八。比法定节日淡一档的颜色。
        case traditional
    }

    /// 格子里用的两字短名。
    let shortName: String
    /// 编辑页标题用的全名。
    let name: String
    let kind: Kind
}

/// 农历。统一用系统的 `Calendar(identifier: .chinese)`，不再自带农历表。
enum LunarCalendar {
    struct Day: Hashable, Sendable {
        let month: Int
        let day: Int
        let isLeapMonth: Bool
    }

    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .chinese)
        calendar.timeZone = .autoupdatingCurrent
        return calendar
    }()

    private static let monthNames = ["正月", "二月", "三月", "四月", "五月", "六月",
                                     "七月", "八月", "九月", "十月", "冬月", "腊月"]
    private static let dayNames = [
        "初一", "初二", "初三", "初四", "初五", "初六", "初七", "初八", "初九", "初十",
        "十一", "十二", "十三", "十四", "十五", "十六", "十七", "十八", "十九", "二十",
        "廿一", "廿二", "廿三", "廿四", "廿五", "廿六", "廿七", "廿八", "廿九", "三十",
    ]

    static func day(for key: String) -> Day? {
        guard let date = ScheduleCalendar.date(from: key) else { return nil }
        let parts = calendar.dateComponents([.month, .day], from: date)
        guard let month = parts.month, let day = parts.day else { return nil }
        return Day(month: month, day: day, isLeapMonth: parts.isLeapMonth ?? false)
    }

    /// 格子里日期下面那一行：初一写月份（闰月加「闰」），其余写日子。
    static func text(for key: String) -> String {
        guard let day = day(for: key) else { return "" }
        if day.day == 1 {
            let name = monthNames[(day.month - 1) % 12]
            return day.isLeapMonth ? "闰" + name : name
        }
        return dayNames[(day.day - 1) % 30]
    }
}

enum Festivals {

    private static let lock = NSLock()
    private static var cache: [String: Festival?] = [:]

    /// 这一天是什么节日。日历每翻一页要把三十来天各查一遍，查过的记下来。
    static func festival(on key: String) -> Festival? {
        if let cached = lock.withLock({ cache[key] }) { return cached }
        let value = compute(key)
        lock.withLock { cache[key] = value }
        return value
    }

    private static func compute(_ key: String) -> Festival? {
        guard let parts = ScheduleCalendar.components(from: key) else { return nil }
        let month = parts.month + 1, day = parts.day

        // 农历节日在前：2020 年 10 月 1 日既是国庆又是中秋，格子里只有一个位置，写中秋。
        if let lunar = LunarCalendar.day(for: key), !lunar.isLeapMonth {
            switch (lunar.month, lunar.day) {
            case (1, 1): return Festival(shortName: "春节", name: "春节", kind: .statutory)
            case (5, 5): return Festival(shortName: "端午", name: "端午节", kind: .statutory)
            case (8, 15): return Festival(shortName: "中秋", name: "中秋节", kind: .statutory)
            default: break
            }
        }
        // 除夕是正月初一的前一天，腊月小的年份就是廿九。
        if let next = LunarCalendar.day(for: ScheduleCalendar.adding(days: 1, to: key)),
           !next.isLeapMonth, next.month == 1, next.day == 1 {
            return Festival(shortName: "除夕", name: "除夕", kind: .statutory)
        }
        // 清明是节气不是农历日子，系统农历没有节气接口，沿用本地的清明表。
        if Holidays.isQingming(key) { return Festival(shortName: "清明", name: "清明节", kind: .statutory) }
        switch (month, day) {
        case (1, 1): return Festival(shortName: "元旦", name: "元旦", kind: .statutory)
        case (5, 1): return Festival(shortName: "劳动", name: "劳动节", kind: .statutory)
        case (10, 1): return Festival(shortName: "国庆", name: "国庆节", kind: .statutory)
        default: break
        }

        if let lunar = LunarCalendar.day(for: key), !lunar.isLeapMonth {
            switch (lunar.month, lunar.day) {
            case (1, 15): return Festival(shortName: "元宵", name: "元宵节", kind: .traditional)
            case (7, 7): return Festival(shortName: "七夕", name: "七夕", kind: .traditional)
            case (7, 15): return Festival(shortName: "中元", name: "中元节", kind: .traditional)
            case (9, 9): return Festival(shortName: "重阳", name: "重阳节", kind: .traditional)
            case (12, 8): return Festival(shortName: "腊八", name: "腊八节", kind: .traditional)
            default: break
            }
        }
        return nil
    }
}
