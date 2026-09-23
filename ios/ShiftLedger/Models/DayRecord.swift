import Foundation

/// 一天记录的来源。
enum RecordSource: String, Codable, Sendable {
    /// 循环模板生成。
    case cycle
    /// 用户逐日手动记录或改写。
    case manual
    /// 从 v1 数据迁移而来。
    case legacy
}

/// 某一天的排班记录。字段与 web 版 `DayRecord` 完全一致。
struct DayRecord: Codable, Hashable, Sendable, Identifiable {
    /// "yyyy-MM-dd"，同时作为主键。
    var date: String
    var shiftId: String
    /// 次要班次。少数人一天上两种班，默认没有；只影响日历上多显示一枚色标，
    /// 出勤判定、班次构成仍然按主要班次算。网页版没有这个字段，导入导出时原样忽略。
    var secondaryShiftId: String?
    var hours: Double
    var tagIds: [String]
    /// 是否已确认完成。未确认但日期已过的记录在统计里同样计入实际工时。
    var completed: Bool
    /// 是否计划出勤。取消排班的日子为 false。
    var planned: Bool
    var note: String?
    /// 手动记录制下这一天登记的加班小时数。
    var manualOvertime: Double?
    var source: RecordSource
    var cycleId: String?

    var id: String { date }

    init(date: String,
         shiftId: String,
         secondaryShiftId: String? = nil,
         hours: Double,
         tagIds: [String] = [],
         completed: Bool = false,
         planned: Bool = true,
         note: String? = nil,
         manualOvertime: Double? = nil,
         source: RecordSource = .manual,
         cycleId: String? = nil) {
        self.date = date
        self.shiftId = shiftId
        self.secondaryShiftId = secondaryShiftId
        self.hours = hours
        self.tagIds = tagIds
        self.completed = completed
        self.planned = planned
        self.note = note
        self.manualOvertime = manualOvertime
        self.source = source
        self.cycleId = cycleId
    }

    /// 统计"实际工时"时算不算数：计划出勤、有工时，且已确认或日期已过。
    func countsAsCompleted(today: String) -> Bool {
        planned && (completed || date < today)
    }

    var monthKey: String { String(date.prefix(7)) }
}
