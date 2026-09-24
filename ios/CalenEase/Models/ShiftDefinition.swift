import Foundation

/// 一个班次对象。字段与 web 版 `app/lib/schedule.ts` 的 `Shift` 一一对应，
/// 备份 JSON 两端可以直接互导。
struct ShiftDefinition: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var shortName: String
    /// 十六进制色值，与 web 版同一套强调色。
    var color: String
    /// "HH:mm"，休息类班次为空串。
    var startTime: String
    var endTime: String
    var crossesMidnight: Bool
    var isRest: Bool
    var defaultHours: Double
    var countsAsWork: Bool
    var note: String?
    /// v1 数据迁移过来时的旧类型标记（day / night / rest …）。
    var legacyType: String?

    init(id: String,
         name: String,
         shortName: String,
         color: String,
         startTime: String = "",
         endTime: String = "",
         crossesMidnight: Bool = false,
         isRest: Bool = false,
         defaultHours: Double = 0,
         countsAsWork: Bool = true,
         note: String? = nil,
         legacyType: String? = nil) {
        self.id = id
        self.name = name
        self.shortName = shortName
        self.color = color
        self.startTime = startTime
        self.endTime = endTime
        self.crossesMidnight = crossesMidnight
        self.isRest = isRest
        self.defaultHours = defaultHours
        self.countsAsWork = countsAsWork
        self.note = note
        self.legacyType = legacyType
    }

    /// 班次时长（小时）。跨零点或结束时间不晚于开始时间时按跨天算。
    var duration: Double {
        ShiftDefinition.duration(startTime: startTime, endTime: endTime, crossesMidnight: crossesMidnight)
    }

    static func duration(startTime: String, endTime: String, crossesMidnight: Bool) -> Double {
        guard let start = minutes(of: startTime), let end = minutes(of: endTime) else { return 0 }
        var finish = end
        if crossesMidnight || finish <= start { finish += 24 * 60 }
        return max(0, Double(finish - start) / 60)
    }

    private static func minutes(of clock: String) -> Int? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else { return nil }
        return hour * 60 + minute
    }

    /// 日历上显示的时间区间，例如 `8~20`。对应 web 版的 `compactShiftRange`。
    var compactRange: String {
        guard !startTime.isEmpty, !endTime.isEmpty else { return "" }
        let endAs24 = !crossesMidnight && startTime != "00:00"
        return "\(ShiftDefinition.compactClock(startTime))~\(ShiftDefinition.compactClock(endTime, asEnd: endAs24))"
    }

    /// 详情里显示的完整区间，例如 `08:00–20:00`。
    var fullRange: String {
        guard !startTime.isEmpty, !endTime.isEmpty else { return "" }
        return "\(startTime)–\(endTime)"
    }

    static func compactClock(_ clock: String, asEnd: Bool = false) -> String {
        guard let total = minutes(of: clock) else { return "" }
        let hour = total / 60
        let minute = total % 60
        if asEnd, hour == 0, minute == 0 { return "24" }
        // 先把 时+分 换算成小时，再按半小时取整；漏掉这对括号会把小时数除以 2
        let rounded = ((Double(hour) + Double(minute) / 60) * 2).rounded() / 2
        return HoursFormatter.compact(rounded)
    }
}

/// 工时数字的统一写法：整数不带小数，其余保留一位。
enum HoursFormatter {
    static func compact(_ value: Double) -> String {
        // 负数用真正的减号，不用连字符——工时可以是负的（上不满基本工时）
        let sign = value < 0 ? "−" : ""
        let magnitude = abs(value)
        if magnitude == magnitude.rounded() { return sign + String(Int(magnitude)) }
        return sign + String(format: "%.1f", magnitude)
    }

    /// 带单位的写法，用于统计卡片。
    static func hours(_ value: Double) -> String { "\(compact(value))h" }
}
