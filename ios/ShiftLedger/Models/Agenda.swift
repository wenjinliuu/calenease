import Foundation

// MARK: - 日程

/// 一条日程。和班次记录分开存：班次一天一条，日程一天可以很多条、可以跨天、可以重复。
struct CalendarEvent: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var title: String
    /// 第一次发生的开始日期 "yyyy-MM-dd"。
    var startDate: String
    /// 第一次发生的结束日期，含当天，不早于开始日期。跨天日程就是两者不同。
    var endDate: String
    var isAllDay: Bool
    /// "HH:mm"。全天日程不看这两个字段。
    var startTime: String
    var endTime: String
    var color: String
    var note: String?
    var recurrence: EventRecurrence
    /// 提前多少分钟提醒，nil 表示不提醒。全天日程：0 = 当天、1440 = 前一天，时刻取提醒设置里的「全天日程提醒时间」。
    var reminderMinutes: Int?
    /// 重复日程里被单独删掉的那几次（按那一次的开始日期记）。
    var exceptions: [String]

    init(id: String = ShiftCatalog.makeId("event"),
         title: String = "",
         startDate: String,
         endDate: String? = nil,
         isAllDay: Bool = false,
         startTime: String = "09:00",
         endTime: String = "10:00",
         color: String = AccentHex.vividCyan,
         note: String? = nil,
         recurrence: EventRecurrence = EventRecurrence(),
         reminderMinutes: Int? = nil,
         exceptions: [String] = []) {
        self.id = id
        self.title = title
        self.startDate = startDate
        self.endDate = endDate ?? startDate
        self.isAllDay = isAllDay
        self.startTime = startTime
        self.endTime = endTime
        self.color = color
        self.note = note
        self.recurrence = recurrence
        self.reminderMinutes = reminderMinutes
        self.exceptions = exceptions
    }

    /// 一次发生跨几天（0 = 当天结束）。
    var spanDays: Int {
        guard let start = DayNumber.of(startDate), let end = DayNumber.of(endDate) else { return 0 }
        return max(0, end - start)
    }

    /// 列表里显示的时间：「全天」或「08:00–09:30」。
    var timeLabel: String { isAllDay ? "全天" : "\(startTime)–\(endTime)" }
}

/// 日程的重复规则。
struct EventRecurrence: Codable, Hashable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        case none, daily, weekly, monthly, yearly, interval, shift

        var id: String { rawValue }

        var label: String {
            switch self {
            case .none: "不重复"
            case .daily: "每天"
            case .weekly: "每周"
            case .monthly: "每月"
            case .yearly: "每年"
            case .interval: "每隔几天"
            case .shift: "跟随班次"
            }
        }
    }

    var kind: Kind = .none
    /// 每周重复的星期几，周一 = 0 … 周日 = 6。空着就用开始那天的星期。
    var weekdays: [Int] = []
    /// 每隔几天重复。
    var interval: Int = 2
    /// 跟随班次：凡是排了这个班的日子都来一次。
    var shiftId: String?
    /// 相对班次那天的偏移，-1 = 前一天，0 = 当天，1 = 后一天。
    var shiftOffset: Int = 0
    /// 重复到哪天为止（含），nil 表示一直重复。
    var until: String?

    var isRepeating: Bool { kind != .none }
}

// MARK: - 倒计时

/// 倒计时 / 正计时。倒数「距离某天还有几天」，正数「从某天到现在已经几天」。
struct Countdown: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Identifiable, Sendable {
        /// 倒数：还有几天。
        case countdown
        /// 正数：已经几天。
        case countUp

        var id: String { rawValue }
        var label: String { self == .countdown ? "倒数日" : "正数日" }
    }

    var id: String
    var title: String
    var date: String
    var kind: Kind
    /// 每年重复：生日、纪念日。倒数时自动算下一次。
    var repeatsYearly: Bool
    var color: String
    /// 置顶的排在最前面。
    var pinned: Bool
    /// 到那天发一条提醒（倒数日才有）。
    var remind: Bool
    var note: String?

    init(id: String = ShiftCatalog.makeId("countdown"),
         title: String = "",
         date: String,
         kind: Kind = .countdown,
         repeatsYearly: Bool = false,
         color: String = AccentHex.vividOrange,
         pinned: Bool = false,
         remind: Bool = true,
         note: String? = nil) {
        self.id = id
        self.title = title
        self.date = date
        self.kind = kind
        self.repeatsYearly = repeatsYearly
        self.color = color
        self.pinned = pinned
        self.remind = remind
        self.note = note
    }
}

// MARK: - 提醒设置

/// 设置页「提醒」那一页的全部开关。提醒都是本机通知，在设备上排好，不经过服务器。
struct ReminderSettings: Codable, Hashable, Sendable {
    /// 上班前提醒。
    var shiftStartEnabled = false
    var shiftStartMinutes = 60
    /// 不提醒的班次（默认所有上班的班次都提醒）。
    var shiftStartExcluded: [String] = []
    /// 下班打卡提醒。
    var clockOutEnabled = false
    var clockOutMinutes = 10
    /// 新建日程时默认的提前提醒分钟数，nil 表示默认不提醒。
    var eventDefaultMinutes: Int? = 15
    /// 全天日程在这个时刻提醒。
    var allDayEventTime = "09:00"
    /// 倒数日当天提醒。
    var countdownEnabled = true
    var countdownTime = "09:00"

    var anyEnabled: Bool { shiftStartEnabled || clockOutEnabled || countdownEnabled }
}

/// 功能开关。
struct FeatureSettings: Codable, Hashable, Sendable {
    /// 排班功能。固定作息的人可以关掉：班次、循环排班、统计页都收起来。
    var shiftsEnabled = true
}
