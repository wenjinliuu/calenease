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
    /// 地点，纯文字；可以一键在「地图」里打开。
    var location: String?
    /// 链接：会议链接、网页。
    var url: String?
    /// 事项页时间线上那颗圆里的图标（SF Symbol 名），nil 用默认图标。
    var symbol: String?
    /// 已完成的那几次（按那一次的开始日期记）。事项页右边那个圈打勾。
    var completions: [String]

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
         exceptions: [String] = [],
         location: String? = nil,
         url: String? = nil,
         symbol: String? = nil,
         completions: [String] = []) {
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
        self.location = location
        self.url = url
        self.symbol = symbol
        self.completions = completions
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

// MARK: - 解码兜底
//
// 这几样都是整份文档里的一部分，以后还会加字段。自动合成的解码要求每个键都在，
// 老版本存下的文件缺一个键就整条读不出来——所以逐个字段兜底。

extension CalendarEvent {
    enum CodingKeys: String, CodingKey {
        case id, title, startDate, endDate, isAllDay, startTime, endTime, color, note
        case recurrence, reminderMinutes, exceptions, location, url, symbol, completions
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let start = try c.decode(String.self, forKey: .startDate)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? ShiftCatalog.makeId("event"),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  startDate: start,
                  endDate: try c.decodeIfPresent(String.self, forKey: .endDate),
                  isAllDay: try c.decodeIfPresent(Bool.self, forKey: .isAllDay) ?? false,
                  startTime: try c.decodeIfPresent(String.self, forKey: .startTime) ?? "09:00",
                  endTime: try c.decodeIfPresent(String.self, forKey: .endTime) ?? "10:00",
                  color: try c.decodeIfPresent(String.self, forKey: .color) ?? AccentHex.vividCyan,
                  note: try c.decodeIfPresent(String.self, forKey: .note),
                  recurrence: (try? c.decodeIfPresent(EventRecurrence.self, forKey: .recurrence)) ?? EventRecurrence(),
                  reminderMinutes: try c.decodeIfPresent(Int.self, forKey: .reminderMinutes),
                  exceptions: try c.decodeIfPresent([String].self, forKey: .exceptions) ?? [],
                  location: try c.decodeIfPresent(String.self, forKey: .location),
                  url: try c.decodeIfPresent(String.self, forKey: .url),
                  symbol: try c.decodeIfPresent(String.self, forKey: .symbol),
                  completions: try c.decodeIfPresent([String].self, forKey: .completions) ?? [])
    }
}

extension EventRecurrence {
    enum CodingKeys: String, CodingKey {
        case kind, weekdays, interval, shiftId, shiftOffset, until
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        kind = (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .none
        weekdays = try c.decodeIfPresent([Int].self, forKey: .weekdays) ?? []
        interval = try c.decodeIfPresent(Int.self, forKey: .interval) ?? 2
        shiftId = try c.decodeIfPresent(String.self, forKey: .shiftId)
        shiftOffset = try c.decodeIfPresent(Int.self, forKey: .shiftOffset) ?? 0
        until = try c.decodeIfPresent(String.self, forKey: .until)
    }
}

extension Countdown {
    enum CodingKeys: String, CodingKey {
        case id, title, date, kind, repeatsYearly, color, pinned, remind, note
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init(id: try c.decodeIfPresent(String.self, forKey: .id) ?? ShiftCatalog.makeId("countdown"),
                  title: try c.decodeIfPresent(String.self, forKey: .title) ?? "",
                  date: try c.decode(String.self, forKey: .date),
                  kind: (try? c.decodeIfPresent(Kind.self, forKey: .kind)) ?? .countdown,
                  repeatsYearly: try c.decodeIfPresent(Bool.self, forKey: .repeatsYearly) ?? false,
                  color: try c.decodeIfPresent(String.self, forKey: .color) ?? AccentHex.vividOrange,
                  pinned: try c.decodeIfPresent(Bool.self, forKey: .pinned) ?? false,
                  remind: try c.decodeIfPresent(Bool.self, forKey: .remind) ?? true,
                  note: try c.decodeIfPresent(String.self, forKey: .note))
    }
}

extension ReminderSettings {
    enum CodingKeys: String, CodingKey {
        case shiftStartEnabled, shiftStartMinutes, shiftStartExcluded, clockOutEnabled, clockOutMinutes
        case eventDefaultMinutes, allDayEventTime, countdownEnabled, countdownTime
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        shiftStartEnabled = try c.decodeIfPresent(Bool.self, forKey: .shiftStartEnabled) ?? shiftStartEnabled
        shiftStartMinutes = try c.decodeIfPresent(Int.self, forKey: .shiftStartMinutes) ?? shiftStartMinutes
        shiftStartExcluded = try c.decodeIfPresent([String].self, forKey: .shiftStartExcluded) ?? []
        clockOutEnabled = try c.decodeIfPresent(Bool.self, forKey: .clockOutEnabled) ?? clockOutEnabled
        clockOutMinutes = try c.decodeIfPresent(Int.self, forKey: .clockOutMinutes) ?? clockOutMinutes
        // nil 是「默认不提醒」，和「没有这个键」要分开：没有这个键才用默认的 15 分钟
        if c.contains(.eventDefaultMinutes) {
            eventDefaultMinutes = try c.decodeIfPresent(Int.self, forKey: .eventDefaultMinutes)
        }
        allDayEventTime = try c.decodeIfPresent(String.self, forKey: .allDayEventTime) ?? allDayEventTime
        countdownEnabled = try c.decodeIfPresent(Bool.self, forKey: .countdownEnabled) ?? countdownEnabled
        countdownTime = try c.decodeIfPresent(String.self, forKey: .countdownTime) ?? countdownTime
    }

    /// 「默认不提醒」要写成 null 存下来，不能省掉这个键，否则读回来又变成 15 分钟。
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(shiftStartEnabled, forKey: .shiftStartEnabled)
        try c.encode(shiftStartMinutes, forKey: .shiftStartMinutes)
        try c.encode(shiftStartExcluded, forKey: .shiftStartExcluded)
        try c.encode(clockOutEnabled, forKey: .clockOutEnabled)
        try c.encode(clockOutMinutes, forKey: .clockOutMinutes)
        try c.encode(eventDefaultMinutes, forKey: .eventDefaultMinutes)
        try c.encode(allDayEventTime, forKey: .allDayEventTime)
        try c.encode(countdownEnabled, forKey: .countdownEnabled)
        try c.encode(countdownTime, forKey: .countdownTime)
    }
}

extension FeatureSettings {
    enum CodingKeys: String, CodingKey {
        case shiftsEnabled
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        shiftsEnabled = try c.decodeIfPresent(Bool.self, forKey: .shiftsEnabled) ?? true
    }
}
