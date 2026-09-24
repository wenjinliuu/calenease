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
    /// 新装第一次打开：问一句是倒班还是固定作息。
    var needsOnboarding = false

    /// 当前生效的放假与调休安排。日历格子、基本工时都从这里取；
    /// 下载到新数据时替换，读它的视图跟着重画。
    private(set) var holidays: HolidayCalendar = .empty
    @ObservationIgnored private var holidaySnapshot = HolidayData.Snapshot()
    @ObservationIgnored private var holidayRefreshTask: Task<Void, Never>?

    /// 当前查看的月份（零基）。
    var focusedYear: Int
    var focusedMonth: Int

    var todayKey: String { ScheduleCalendar.todayKey }

    private let fileURL: URL
    private var saveTask: Task<Void, Never>?
    /// 已经补齐过循环记录的「循环 ID|年份」。翻月时同一年不必重算——
    /// 重算一次要生成一整年的记录、全表排序再整份比较，连续翻月时会一下一下地卡。
    /// 文档被别的途径改动（编辑、导入、换循环）时清空。
    @ObservationIgnored private var materializedYears: Set<String> = []

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
        materializedYears.removeAll()
        loadHolidays()
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
            needsOnboarding = !Self.isRunningTests
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
        // 读盘到此为止，后面几步的改动要能落盘。
        isReady = true
        dropRetiredTemplates()
        migratePaletteIfNeeded()
        materializeFocusedYears()
    }

    // MARK: - 放假安排

    /// 单元测试跑在宿主 App 里。别让 App 自己装上放假数据——测试要的是可复现的本地推算，
    /// 用到真实安排的测试自己构造 `HolidayCalendar` 传进去。
    private static var isRunningTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// 读包里的快照和本机缓存。
    private func loadHolidays() {
        guard !Self.isRunningTests else { return }
        installHolidays(HolidayData.loadLocal())
    }

    private func installHolidays(_ snapshot: HolidayData.Snapshot) {
        holidaySnapshot = snapshot
        let calendar = snapshot.calendar
        HolidayCalendar.shared = calendar
        if calendar != holidays { holidays = calendar }
    }

    /// 联网检查放假安排有没有更新。距上次成功检查不到半天就跳过；失败了下次回到前台再试。
    func refreshHolidaysIfNeeded() {
        guard !Self.isRunningTests, !DemoData.isEnabled, holidayRefreshTask == nil else { return }
        let key = "holidays.lastCheckedAt"
        let last = UserDefaults.standard.double(forKey: key)
        guard Date().timeIntervalSince1970 - last >= HolidayData.refreshInterval else { return }
        let current = holidaySnapshot
        holidayRefreshTask = Task { [weak self] in
            do {
                let next = try await HolidayData.refresh(from: current)
                UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: key)
                if let next { self?.installHolidays(next) }
            } catch {
                // 没网、超时、格式不对：保留本地数据，下次再试。
            }
            self?.holidayRefreshTask = nil
        }
    }

    /// 下线的内置模板从老数据里清掉。
    private func dropRetiredTemplates() {
        let retired = ShiftCatalog.retiredTemplateIDs
        guard document.cycleTemplates.contains(where: { retired.contains($0.id) }) else { return }
        update { $0.cycleTemplates.removeAll { retired.contains($0.id) } }
    }

    /// 换色板之后，老文件里存的还是旧色值，补迁一次。
    private func migratePaletteIfNeeded() {
        guard PaletteMigration.isNeeded() else { return }
        defer { PaletteMigration.markDone() }
        let next = PaletteMigration.migrate(document)
        guard next != document else { return }
        document = next
        materializedYears.removeAll()
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
        materializedYears.removeAll()
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

    /// 当前查看的月份写成「年 × 12 + 零基月」，前后相邻的月份就是 ±1。
    var focusedIndex: Int { focusedYear * 12 + focusedMonth }

    /// 本月的同一种写法。
    var currentMonthIndex: Int {
        let parts = ScheduleCalendar.calendar.dateComponents([.year, .month], from: Date())
        return (parts.year ?? focusedYear) * 12 + (parts.month ?? 1) - 1
    }

    /// 当前查看的月份是否早于本月（决定「今天」按钮该往哪个方向滑）。
    func isFocusedBefore(today: Bool = true) -> Bool {
        focusedIndex < currentMonthIndex
    }

    func changeMonth(by delta: Int) {
        focus(index: focusedIndex + delta)
    }

    /// 跳到指定月份。日历翻页、月份选择器、统计页的前后切换都走这里。
    func focus(index: Int) {
        guard index != focusedIndex else { return }
        focusedYear = Int((Double(index) / 12).rounded(.down))
        focusedMonth = index - focusedYear * 12
        materializeFocusedYears()
    }

    func focus(year: Int, month: Int) {
        focus(index: year * 12 + month)
    }

    func goToCurrentMonth() {
        focus(index: currentMonthIndex)
    }

    /// 补齐当前统计年度覆盖到的循环记录，让日历往后翻永远有班。
    func materializeFocusedYears() {
        guard let cycle = document.activeCycle else { return }
        let reporting = WorkHours.reportingCycle(for: document, year: focusedYear, month: focusedMonth)
        let keys = Set([reporting.startYear, reporting.endYear]).map { "\(cycle.id)|\($0)" }
        guard !keys.allSatisfy(materializedYears.contains) else { return }
        let next = CycleGenerator.materializeReportingYears(document,
                                                            year: focusedYear,
                                                            month: focusedMonth)
        materializedYears.formUnion(keys)
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
            for index in document.records.indices where document.records[index].secondaryShiftId == shift.id {
                document.records[index].secondaryShiftId = nil
            }
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

    // MARK: - 日程

    func saveEvent(_ event: CalendarEvent) {
        update { document in
            if let index = document.events.firstIndex(where: { $0.id == event.id }) {
                document.events[index] = event
            } else {
                document.events.append(event)
            }
        }
    }

    func deleteEvent(id: String) {
        update { $0.events.removeAll { $0.id == id } }
    }

    /// 重复日程只删这一次：记进例外，其余照旧。
    func excludeOccurrence(eventId: String, on date: String) {
        update { document in
            guard let index = document.events.firstIndex(where: { $0.id == eventId }) else { return }
            if !document.events[index].exceptions.contains(date) {
                document.events[index].exceptions.append(date)
            }
        }
    }

    /// 事项页右边那个圈：勾上 / 取消这一次的完成。
    func toggleCompletion(eventId: String, on date: String) {
        update { document in
            guard let index = document.events.firstIndex(where: { $0.id == eventId }) else { return }
            if document.events[index].completions.contains(date) {
                document.events[index].completions.removeAll { $0 == date }
            } else {
                document.events[index].completions.append(date)
            }
        }
    }

    /// 某一天的日程。
    func occurrences(on date: String) -> [EventOccurrence] {
        EventEngine.occurrences(of: document.events, on: date, shiftDays: EventEngine.shiftDays(of: document))
    }

    // MARK: - 倒计时

    func saveCountdown(_ countdown: Countdown) {
        update { document in
            if let index = document.countdowns.firstIndex(where: { $0.id == countdown.id }) {
                document.countdowns[index] = countdown
            } else {
                document.countdowns.append(countdown)
            }
        }
    }

    func deleteCountdown(id: String) {
        update { $0.countdowns.removeAll { $0.id == id } }
    }

    // MARK: - 功能与提醒

    func setShiftsEnabled(_ enabled: Bool) {
        update { $0.features.shiftsEnabled = enabled }
    }

    func updateReminders(_ transform: (inout ReminderSettings) -> Void) {
        update { transform(&$0.reminders) }
    }

    func completeOnboarding(shiftsEnabled: Bool) {
        setShiftsEnabled(shiftsEnabled)
        needsOnboarding = false
    }

    func replaceDocument(_ next: ScheduleDocument) {
        update { document in document = next }
        materializeFocusedYears()
    }
}
