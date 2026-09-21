import Foundation
import Observation

/// App 唯一的数据门面。
///
/// 整份数据是一个 `ScheduleDocument`，和 web 版一样：所有修改都是对
/// 整份文档做一次变换（换循环会整段重排，切职业预设会重算班次与标签），
/// 因此按文档整体保存比拆成多张表更贴合业务，也让备份与网页端逐字段对齐。
/// 文件写在应用沙盒的 Application Support 里，随 iCloud 设备备份一起走。
@MainActor
@Observable
final class ScheduleStore {

    private(set) var document: ScheduleDocument
    /// 首次读盘完成前不写盘，避免把默认数据覆盖到用户数据上。
    private(set) var isReady = false
    private(set) var lastSaveError: String?

    /// 当前查看的月份（零基）。
    var focusedYear: Int
    var focusedMonth: Int

    var todayKey: String { ScheduleCalendar.todayKey }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil, document: ScheduleDocument? = nil) {
        let parts = ScheduleCalendar.calendar.dateComponents([.year, .month], from: Date())
        focusedYear = parts.year ?? 2026
        focusedMonth = (parts.month ?? 1) - 1
        self.fileURL = fileURL ?? Self.defaultFileURL()
        if let document {
            self.document = document
            isReady = true
        } else {
            self.document = .makeDefault()
        }
    }

    static func defaultFileURL() -> URL {
        let base = (try? FileManager.default.url(for: .applicationSupportDirectory,
                                                 in: .userDomainMask,
                                                 appropriateFor: nil,
                                                 create: true))
            ?? URL.documentsDirectory
        return base.appendingPathComponent("shift-ledger.json")
    }

    // MARK: - 读写

    func load() {
        // 截图流程用示例数据启动，既不读也不写用户文件。
        if DemoData.isEnabled {
            document = DemoData.document()
            isReady = false
            return
        }
        defer { isReady = true }
        guard let data = try? Data(contentsOf: fileURL) else {
            // 新装：默认数据本来就是新色板，不用再迁。
            PaletteMigration.markDone()
            return
        }
        if let decoded = try? JSONDecoder().decode(ScheduleDocument.self, from: data) {
            document = decoded
        } else if let raw = try? JSONSerialization.jsonObject(with: data) {
            // 文件是更早的结构（或手工放进来的网页版备份）时走清洗流程。
            document = DocumentNormalizer.document(fromBackup: raw)
        } else {
            // 文件在那儿但读不懂，别用默认数据把它盖掉。
            return
        }
        // 读盘到此为止，后面两步的改动要能落盘。
        isReady = true
        migratePaletteIfNeeded()
        materializeFocusedYears()
    }

    /// 换色板之后，老文件里存的还是旧色值，补迁一次。
    private func migratePaletteIfNeeded() {
        guard PaletteMigration.isNeeded() else { return }
        defer { PaletteMigration.markDone() }
        let next = PaletteMigration.migrate(document)
        guard next != document else { return }
        document = next
        // 标记已经写下了，这一份必须同步落盘，不能只排一次防抖写。
        flush()
    }

    /// 合并写盘：连续编辑只落一次。
    private func scheduleSave() {
        guard isReady else { return }
        saveTask?.cancel()
        let snapshot = document
        saveTask = Task { [fileURL] in
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
            do {
                let encoder = JSONEncoder()
                encoder.outputFormatting = [.withoutEscapingSlashes]
                let data = try encoder.encode(snapshot)
                try data.write(to: fileURL, options: .atomic)
                await MainActor.run { self.lastSaveError = nil }
            } catch {
                await MainActor.run { self.lastSaveError = error.localizedDescription }
            }
        }
    }

    /// 所有修改的唯一入口，保证改完必定排一次写盘。
    func update(_ transform: (inout ScheduleDocument) -> Void) {
        var next = document
        transform(&next)
        document = next
        scheduleSave()
    }

    /// 立刻写盘，用于进入后台前。
    func flush() {
        saveTask?.cancel()
        guard isReady else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        if let data = try? encoder.encode(document) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - 月份导航

    var focusedMonthLabel: String { "\(focusedYear)年\(focusedMonth + 1)月" }

    var focusedMonthKey: String { ScheduleCalendar.monthKey(year: focusedYear, month: focusedMonth) }

    /// 当前查看的月份是否早于本月（决定「今天」按钮该往哪个方向滑）。
    func isFocusedBefore(today: Bool = true) -> Bool {
        let parts = ScheduleCalendar.calendar.dateComponents([.year, .month], from: Date())
        let current = (parts.year ?? focusedYear) * 12 + (parts.month ?? 1) - 1
        return focusedYear * 12 + focusedMonth < current
    }

    func changeMonth(by delta: Int) {
        let absolute = focusedYear * 12 + focusedMonth + delta
        focusedYear = absolute / 12
        focusedMonth = absolute % 12
        if focusedMonth < 0 {
            focusedMonth += 12
            focusedYear -= 1
        }
        materializeFocusedYears()
    }

    func goToCurrentMonth() {
        let parts = ScheduleCalendar.calendar.dateComponents([.year, .month], from: Date())
        focusedYear = parts.year ?? focusedYear
        focusedMonth = (parts.month ?? 1) - 1
        materializeFocusedYears()
    }

    /// 补齐当前统计年度覆盖到的循环记录，让日历往后翻永远有班。
    func materializeFocusedYears() {
        guard document.activeCycle != nil else { return }
        let next = CycleGenerator.materializeReportingYears(document,
                                                            year: focusedYear,
                                                            month: focusedMonth)
        guard next != document else { return }
        document = next
        scheduleSave()
    }

    // MARK: - 逐日编辑

    func record(on date: String) -> DayRecord? { document.record(on: date) }

    func shift(_ id: String) -> ShiftDefinition? { document.shift(id) }

    func tags(for record: DayRecord) -> [DutyTag] {
        record.tagIds.compactMap { document.tag($0) }
    }

    /// 把某一天改成指定班次。工时留空时用班次默认工时。
    func assign(shiftId: String, to date: String, hours: Double? = nil) {
        guard let shift = document.shift(shiftId) else { return }
        update { document in
            var record = document.record(on: date)
                ?? DayRecord(date: date, shiftId: shiftId, hours: shift.defaultHours, source: .manual)
            record.shiftId = shiftId
            record.hours = hours ?? shift.defaultHours
            record.planned = true
            record.source = .manual
            document.upsert(record)
        }
    }

    func save(_ record: DayRecord) {
        update { document in
            var next = record
            next.source = .manual
            document.upsert(next)
        }
    }

    func clearDay(_ date: String) {
        update { $0.removeRecord(on: date) }
    }

    /// 区间批量修改：整段统一换班次，可选一并设置工时与标签。
    func applyBatch(dates: [String], shiftId: String, hours: Double?, tagIds: [String]?) {
        guard let shift = document.shift(shiftId) else { return }
        update { document in
            for date in dates {
                var record = document.record(on: date)
                    ?? DayRecord(date: date, shiftId: shiftId, hours: shift.defaultHours, source: .manual)
                record.shiftId = shiftId
                record.hours = hours ?? shift.defaultHours
                record.planned = true
                record.source = .manual
                if let tagIds { record.tagIds = tagIds }
                document.upsert(record)
            }
        }
    }

    // MARK: - 循环

    /// 应用一套循环：起始日之后按新循环重排到统计年度末。
    func applyCycle(name: String, startDate: String, shiftIds: [String]) {
        let cycle = ActiveCycle(id: ShiftCatalog.makeId("cycle"),
                                name: name,
                                startDate: startDate,
                                shiftIds: shiftIds)
        let throughYear = max(focusedYear,
                              (Int(startDate.prefix(4)) ?? focusedYear)) + 1
        update { document in
            document = CycleGenerator.replace(document, with: cycle, throughYear: throughYear)
        }
    }

    func stopCycle() {
        update { document in
            document.activeCycle = nil
        }
    }

    // MARK: - 设置

    func applyCareerPreset(_ preset: CareerPreset) {
        update { document in
            document = CareerPresets.apply(preset, to: document)
        }
    }

    /// 保存班次。改了默认工时时，把还在用旧默认值的日子一起更新——
    /// 否则「把白班从 12 小时改成 11.5」只会改设置页的数字，
    /// 已经排出去的班还按旧工时算，统计和加班就对不上了。
    /// 单独调整过工时的那些天保持原样。
    func saveShift(_ shift: ShiftDefinition) {
        update { document in
            guard let index = document.shifts.firstIndex(where: { $0.id == shift.id }) else {
                document.shifts.append(shift)
                return
            }
            let previousHours = document.shifts[index].defaultHours
            document.shifts[index] = shift
            guard previousHours != shift.defaultHours else { return }
            for recordIndex in document.records.indices
            where document.records[recordIndex].shiftId == shift.id
                && document.records[recordIndex].hours == previousHours {
                document.records[recordIndex].hours = shift.defaultHours
            }
        }
    }

    /// 上一次保存班次时，跟着更新了多少天。供界面提示用。
    func recordsMatchingDefaultHours(of shift: ShiftDefinition) -> Int {
        document.records.filter { $0.shiftId == shift.id && $0.hours == shift.defaultHours }.count
    }

    /// 删除班次。已经排过这个班的日子会一并清掉，避免留下悬空引用。
    func deleteShift(_ shift: ShiftDefinition) {
        update { document in
            document.shifts.removeAll { $0.id == shift.id }
            document.records.removeAll { $0.shiftId == shift.id }
            document.cycleTemplates.removeAll { $0.shiftIds.contains(shift.id) }
            if document.activeCycle?.shiftIds.contains(shift.id) == true {
                document.activeCycle = nil
            }
        }
    }

    /// 这个班次有多少天在用，删除前提示用。
    func usageCount(of shift: ShiftDefinition) -> Int {
        document.records.filter { $0.shiftId == shift.id }.count
    }

    func saveTag(_ tag: DutyTag) {
        update { document in
            if let index = document.tags.firstIndex(where: { $0.id == tag.id }) {
                document.tags[index] = tag
            } else {
                document.tags.append(tag)
            }
        }
    }

    func deleteTag(_ tag: DutyTag) {
        update { document in
            document.tags.removeAll { $0.id == tag.id }
            for index in document.records.indices {
                document.records[index].tagIds.removeAll { $0 == tag.id }
            }
        }
    }

    func setMonthlyTarget(_ hours: Double?, year: Int, month: Int) {
        let key = ScheduleCalendar.monthKey(year: year, month: month)
        update { document in
            if let hours { document.targets[key] = hours } else { document.targets.removeValue(forKey: key) }
        }
    }

    func replaceDocument(_ next: ScheduleDocument) {
        update { document in document = next }
        materializeFocusedYears()
    }
}
