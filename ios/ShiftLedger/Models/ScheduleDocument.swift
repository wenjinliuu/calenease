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
