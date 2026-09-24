import Foundation

/// App 的完整数据。字段名与 web 版 `AppData` 一致，
/// 因此 iOS 导出的备份可以直接在网页端导入，反之亦然。
struct ScheduleDocument: Codable, Hashable, Sendable {
    static let version = 2

    var dataVersion: Int = ScheduleDocument.version
    var careerPreset: CareerPreset = .manufacturing
    var shifts: [ShiftDefinition] = []
    var tags: [DutyTag] = []
    var cycleTemplates: [CycleTemplate] = []
    var activeCycle: ActiveCycle?
    var display = CalendarDisplaySettings()
    var work = WorkSettings()
    /// "yyyy-MM" → 手动修正的当月基本工时。
    var targets: [String: Double] = [:]
    var records: [DayRecord] = []
    /// 日程、倒计时、提醒、功能开关。网页版没有这几项，导入导出时各自忽略。
    var events: [CalendarEvent] = []
    var countdowns: [Countdown] = []
    var reminders = ReminderSettings()
    var features = FeatureSettings()

    /// 首次启动的数据：空日历 + 一组常用班次和模板。
    static func makeDefault() -> ScheduleDocument {
        let shifts = ShiftCatalog.base()
        let shiftIds = Set(shifts.map(\.id))
        var document = ScheduleDocument()
        document.shifts = shifts
        document.tags = ShiftCatalog.baseTags()
        document.cycleTemplates = ShiftCatalog.builtInTemplates().filter {
            ShiftCatalog.starterTemplateIDs.contains($0.id)
                && $0.shiftIds.allSatisfy(shiftIds.contains)
        }
        return document
    }

    // MARK: - 查询

    func event(_ id: String) -> CalendarEvent? { events.first { $0.id == id } }

    func shift(_ id: String) -> ShiftDefinition? { shifts.first { $0.id == id } }
    func tag(_ id: String) -> DutyTag? { tags.first { $0.id == id } }
    func record(on date: String) -> DayRecord? { records.first { $0.date == date } }

    /// 设置页与选择器里的班次顺序：内置的按固定次序，自定义的排在后面。
    var orderedShifts: [ShiftDefinition] {
        let rank = Dictionary(uniqueKeysWithValues: ShiftID.displayOrder.enumerated().map { ($1, $0) })
        return shifts.enumerated().sorted { left, right in
            let a = rank[left.element.id] ?? 99
            let b = rank[right.element.id] ?? 99
            return a == b ? left.offset < right.offset : a < b
        }.map(\.element)
    }

    func records(in range: ClosedRange<String>) -> [DayRecord] {
        records.filter { range.contains($0.date) }
    }

    func records(inMonths months: [ReportingMonth]) -> [DayRecord] {
        let keys = Set(months.map(\.key))
        return records.filter { keys.contains($0.monthKey) }
    }

    func records(inMonth month: ReportingMonth) -> [DayRecord] {
        records.filter { $0.monthKey == month.key }
    }

    // MARK: - 修改

    mutating func upsert(_ record: DayRecord) {
        if let index = records.firstIndex(where: { $0.date == record.date }) {
            records[index] = record
        } else {
            records.append(record)
            records.sort { $0.date < $1.date }
        }
    }

    mutating func removeRecord(on date: String) {
        records.removeAll { $0.date == date }
    }
}

extension ScheduleDocument {
    enum CodingKeys: String, CodingKey {
        case dataVersion, careerPreset, shifts, tags, cycleTemplates, activeCycle, display, work, targets, records
        case events, countdowns, reminders, features
    }

    /// 后加的四个字段逐个兜底：老版本存下的文件里没有它们，不能因此整份解码失败。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init()
        dataVersion = try container.decodeIfPresent(Int.self, forKey: .dataVersion) ?? ScheduleDocument.version
        careerPreset = try container.decodeIfPresent(CareerPreset.self, forKey: .careerPreset) ?? .manufacturing
        shifts = try container.decode([ShiftDefinition].self, forKey: .shifts)
        tags = try container.decodeIfPresent([DutyTag].self, forKey: .tags) ?? []
        cycleTemplates = try container.decodeIfPresent([CycleTemplate].self, forKey: .cycleTemplates) ?? []
        activeCycle = try container.decodeIfPresent(ActiveCycle.self, forKey: .activeCycle)
        display = try container.decodeIfPresent(CalendarDisplaySettings.self, forKey: .display) ?? CalendarDisplaySettings()
        work = try container.decodeIfPresent(WorkSettings.self, forKey: .work) ?? WorkSettings()
        targets = try container.decodeIfPresent([String: Double].self, forKey: .targets) ?? [:]
        records = try container.decodeIfPresent([DayRecord].self, forKey: .records) ?? []
        events = (try? container.decodeIfPresent([CalendarEvent].self, forKey: .events)) ?? []
        countdowns = (try? container.decodeIfPresent([Countdown].self, forKey: .countdowns)) ?? []
        reminders = (try? container.decodeIfPresent(ReminderSettings.self, forKey: .reminders)) ?? ReminderSettings()
        features = (try? container.decodeIfPresent(FeatureSettings.self, forKey: .features)) ?? FeatureSettings()
    }
}
