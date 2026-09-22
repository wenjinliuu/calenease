import XCTest
@testable import ShiftLedger

/// 排班与数据迁移的一致性测试，用例逐条对应 web 版 `tests/schedule.test.ts`。
/// 同一份数据在网页端和 App 上必须得到相同结论，否则备份互导就会走样。
final class ScheduleRulesTests: XCTestCase {

    private func json(_ document: ScheduleDocument) throws -> [String: Any] {
        let data = try JSONEncoder().encode(document)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - 数据清洗与迁移

    func testLegacyColorsMigrateToAccentPalette() throws {
        var raw = try json(.makeDefault())
        var shifts = try XCTUnwrap(raw["shifts"] as? [[String: Any]])
        shifts[0]["color"] = "#ef7d36"
        shifts[1]["color"] = "#5368e8"
        raw["shifts"] = shifts
        raw["tags"] = [["id": "tag-legacy", "name": "旧标签", "shortName": "旧", "color": "#d14f72"]]

        let normalized = DocumentNormalizer.document(from: raw)
        // v1 的 #ef7d36 是个橙，新色板里对应南瓜；旧色板没有合适的橙才退到黄。
        XCTAssertEqual(normalized.shifts[0].color, AccentHex.pumpkin)
        XCTAssertEqual(normalized.shifts[1].color, AccentHex.royal)
        XCTAssertEqual(normalized.tags[0].color, AccentHex.rose)
    }

    func testMarkInkIsWhiteOnEveryShiftColor() {
        // 浅色下色标里的简称字统一白字，不再逐色压同色深字。
        for hex in AccentHex.shiftPalette {
            XCTAssertEqual(Tone.markInk(on: hex), "#FFFFFF", "\(hex) 该用白字")
        }
    }

    func testShiftToneIsCachedPerColor() {
        // 日历每一格每一帧都取色，同一个色值必须直接命中缓存，结果前后一致。
        let first = Tone.shift(AccentHex.vividOrange)
        let second = Tone.shift(AccentHex.vividOrange)
        XCTAssertEqual(first.mark, second.mark)
        XCTAssertEqual(first.text, second.text)
    }

    func testVividGroupLeadsThePaletteAndTheClassicOneIsStillThere() {
        // 活力组排在前面（内置班次用的就是这些），原来的十四色一个没少，跟在后面。
        XCTAssertEqual(Array(AccentHex.shiftPalette.prefix(AccentHex.vividPalette.count)),
                       AccentHex.vividPalette)
        XCTAssertEqual(Array(AccentHex.shiftPalette.suffix(AccentHex.classicPalette.count)),
                       AccentHex.classicPalette)
        XCTAssertEqual(Set(AccentHex.classicPalette).intersection(AccentHex.vividPalette), [])

        let shifts = Dictionary(uniqueKeysWithValues: ShiftCatalog.all().map { ($0.id, $0.color) })
        XCTAssertEqual(shifts[ShiftID.day], AccentHex.vividOrange)
        XCTAssertEqual(shifts[ShiftID.night], AccentHex.navy)
        // 请假要一个偏深的，焦糖是这组里明度最低的。
        XCTAssertEqual(shifts[ShiftID.leave], AccentHex.caramel)
        XCTAssertEqual(shifts[ShiftID.rest], AccentHex.neutral)
    }

    func testPaletteMigrationMovesBuiltInShiftsToTheirNewDefaults() {
        var document = ScheduleDocument.makeDefault()
        // 换色板之前装过的用户，文件里存的是上一代色值。
        document.shifts = document.shifts.map { shift in
            var shift = shift
            switch shift.id {
            case ShiftID.day: shift.color = AccentHex.pumpkin    // 上一代的白班色
            case ShiftID.night: shift.color = AccentHex.indigo   // 上一代的夜班色
            case ShiftID.rest, ShiftID.leave: shift.color = "#8e8e8e"
            default: break
            }
            return shift
        }
        document.shifts.append(ShiftDefinition(id: "shift-abc123", name: "自定班", shortName: "自",
                                               color: "#ed7c37", defaultHours: 8))
        document.shifts.append(ShiftDefinition(id: "shift-def456", name: "已改过", shortName: "改",
                                               color: AccentHex.mint, defaultHours: 8))
        document.tags = [DutyTag(id: "tag-1", name: "带教", shortName: "教", color: "#a67df2")]

        let migrated = PaletteMigration.migrate(document)
        let color = { (id: String) in migrated.shifts.first { $0.id == id }?.color }

        // 内置班次认 ID，不认色值：上一代的南瓜橙要迁到这一代的活力橙。
        XCTAssertEqual(color(ShiftID.day), AccentHex.vividOrange)
        XCTAssertEqual(color(ShiftID.night), AccentHex.navy)
        XCTAssertEqual(color(ShiftID.leave), AccentHex.caramel)
        XCTAssertEqual(color(ShiftID.rest), AccentHex.neutral)
        // 自定义班次没有 ID 可认，走色值映射。
        XCTAssertEqual(color("shift-abc123"), AccentHex.pumpkin)
        // 已经是新色板里的颜色，说明用户自己挑过，不覆盖。
        XCTAssertEqual(color("shift-def456"), AccentHex.mint)
        XCTAssertEqual(migrated.tags[0].color, AccentHex.purple)
    }

    func testPaletteMigrationIsIdempotent() {
        let once = PaletteMigration.migrate(.makeDefault())
        XCTAssertEqual(once, .makeDefault())
        XCTAssertEqual(PaletteMigration.migrate(once), once)
    }

    func testRestShiftAlwaysNormalizesToGray() throws {
        var raw = try json(.makeDefault())
        var shifts = try XCTUnwrap(raw["shifts"] as? [[String: Any]])
        let index = try XCTUnwrap(shifts.firstIndex { $0["id"] as? String == ShiftID.rest })
        shifts[index]["color"] = AccentHex.yellow
        raw["shifts"] = shifts

        let normalized = DocumentNormalizer.document(from: raw)
        XCTAssertEqual(normalized.shift(ShiftID.rest)?.color, AccentHex.gray)
    }

    func testLegacyV1DataMigratesToStableShiftIDs() {
        let document = DocumentNormalizer.migrateLegacy(
            settings: [
                "dayHours": 12,
                "nightHours": 12,
                "cycleStart": "2026-01-01",
                "cycle": ["day", "rest", "night"],
            ],
            records: [["date": "2026-01-01", "shift": "day", "hours": 12, "planned": true]]
        )
        XCTAssertEqual(document.dataVersion, ScheduleDocument.version)
        XCTAssertEqual(document.records.first?.shiftId, ShiftID.day)
        XCTAssertEqual(document.shift(ShiftID.day)?.defaultHours, 12)
        XCTAssertEqual(document.activeCycle?.shiftIds, [ShiftID.day, ShiftID.rest, ShiftID.night])
    }

    func testMissingDisplaySettingsFallBackToDefaults() throws {
        var raw = try json(.makeDefault())
        raw.removeValue(forKey: "display")
        let normalized = DocumentNormalizer.document(from: raw)
        XCTAssertTrue(normalized.display.showHolidays)
        XCTAssertTrue(normalized.display.showShift)
        XCTAssertFalse(normalized.display.showHours)
    }

    func testMissingAnnualStartMonthFallsBackToJanuary() throws {
        var raw = try json(.makeDefault())
        var work = try XCTUnwrap(raw["work"] as? [String: Any])
        work.removeValue(forKey: "annualStartMonth")
        raw["work"] = work
        XCTAssertEqual(DocumentNormalizer.document(from: raw).work.annualStartMonth, 1)
    }

    func testDisablingHoursAlsoDisablesOvertime() throws {
        var raw = try json(.makeDefault())
        var work = try XCTUnwrap(raw["work"] as? [String: Any])
        work["trackHours"] = false
        work["trackOvertime"] = true
        raw["work"] = work

        let normalized = DocumentNormalizer.document(from: raw)
        XCTAssertFalse(normalized.work.trackHours)
        XCTAssertFalse(normalized.work.trackOvertime)
    }

    func testEnablingHoursAlsoEnablesOvertime() throws {
        var raw = try json(.makeDefault())
        var work = try XCTUnwrap(raw["work"] as? [String: Any])
        work["trackHours"] = true
        work["trackOvertime"] = false
        raw["work"] = work

        let normalized = DocumentNormalizer.document(from: raw)
        XCTAssertTrue(normalized.work.trackHours)
        XCTAssertTrue(normalized.work.trackOvertime)
    }

    func testComprehensiveSystemAlwaysReportsByMonth() throws {
        var raw = try json(.makeDefault())
        var work = try XCTUnwrap(raw["work"] as? [String: Any])
        work["system"] = "comprehensive"
        work["period"] = "year"
        raw["work"] = work
        XCTAssertEqual(DocumentNormalizer.document(from: raw).work.period, .month)
    }

    // MARK: - 循环生成

    func testFourDayFourNightCycleRepeatsByShiftID() throws {
        let document = ScheduleDocument.makeDefault()
        let template = try XCTUnwrap(document.cycleTemplates.first { $0.id == "tpl-four-two" })
        let cycle = ActiveCycle(id: "cycle-a", name: template.name,
                                startDate: "2026-08-01", shiftIds: template.shiftIds)

        let records = CycleGenerator.records(cycle: cycle, shifts: document.shifts,
                                             from: "2026-08-01", to: "2026-08-13")
        XCTAssertEqual(records.prefix(12).map(\.shiftId), template.shiftIds)
        XCTAssertEqual(records[12].shiftId, ShiftID.day)
    }

    func testManualOverrideSurvivesCycleMaterialization() {
        let document = CareerPresets.apply(.transport, to: .makeDefault())
        let cycle = ActiveCycle(id: "cycle-b", name: "早中晚休", startDate: "2026-12-30",
                                shiftIds: [ShiftID.morning, ShiftID.middle, ShiftID.late, ShiftID.rest])
        var next = CycleGenerator.replace(document, with: cycle, throughYear: 2027)
        next.upsert(DayRecord(date: "2027-01-02", shiftId: ShiftID.day, hours: 12, source: .manual))
        next = CycleGenerator.materialize(next, year: 2027)

        XCTAssertEqual(next.record(on: "2027-01-02")?.shiftId, ShiftID.day)
        XCTAssertEqual(next.record(on: "2027-01-03")?.shiftId, ShiftID.morning)
    }

    func testDefaultShiftsAreTheFourCoreOnesAndPresetsAddMore() {
        let document = ScheduleDocument.makeDefault()
        // 首启只给最常用的四个，早/中/晚在设置页按需添加。
        XCTAssertEqual(document.shifts.map(\.id),
                       [ShiftID.day, ShiftID.night, ShiftID.rest, ShiftID.leave])
        XCTAssertEqual(document.tags.map(\.name), ["代班", "责班", "值班"])

        let transport = CareerPresets.apply(.transport, to: document)
        XCTAssertTrue(transport.shifts.contains { $0.id == ShiftID.morning })
        // 三班倒的三套内置模板已经下线，职业预设不会再把它们加回来。
        XCTAssertFalse(transport.cycleTemplates.contains { ShiftCatalog.retiredTemplateIDs.contains($0.id) })
    }

    func testOnlyTheThreeTwoShiftTemplatesAreBuiltIn() {
        XCTAssertEqual(ShiftCatalog.builtInTemplates().map(\.id),
                       ["tpl-four-two", "tpl-two-rest-two", "tpl-one-one-two"])
        XCTAssertEqual(ScheduleDocument.makeDefault().cycleTemplates.count, 3)
    }

    // MARK: - 年度周期

    func testAnnualCycleStartingInDecemberSpansTwoYears() {
        let cycle = AnnualCycle.containing(year: 2026, month: 7, annualStartMonth: 12)
        XCTAssertEqual(cycle.startDate, "2025-12-01")
        XCTAssertEqual(cycle.endDate, "2026-11-30")
        XCTAssertEqual(cycle.months.count, 12)
        XCTAssertEqual(cycle.months.first?.key, "2025-12")
        XCTAssertEqual(cycle.months.last?.key, "2026-11")
    }

    func testAnnualCycleAdvancesOnceStartMonthIsReached() {
        let cycle = AnnualCycle.containing(year: 2026, month: 11, annualStartMonth: 12)
        XCTAssertEqual(cycle.startDate, "2026-12-01")
        XCTAssertEqual(cycle.endDate, "2027-11-30")
    }

    // MARK: - 职业预设

    func testMedicalPresetAddsShiftsAndTagsWithoutDuplicating() {
        let once = CareerPresets.apply(.medical, to: .makeDefault())
        let twice = CareerPresets.apply(.medical, to: once)
        XCTAssertTrue(twice.shifts.contains { $0.id == ShiftID.smallNight })
        XCTAssertTrue(twice.shifts.contains { $0.id == ShiftID.duty })
        XCTAssertTrue(twice.shifts.contains { $0.id == ShiftID.clinic })
        XCTAssertTrue(twice.tags.contains { $0.name == "责班" })
        XCTAssertEqual(twice.shifts.filter { $0.id == ShiftID.bigNight }.count, 1)
    }

    func testSwitchingCareerDropsUnusedPresetTags() {
        let medical = CareerPresets.apply(.medical, to: .makeDefault())
        let transport = CareerPresets.apply(.transport, to: medical)
        XCTAssertFalse(transport.tags.contains { $0.id.hasPrefix("tag-medical-") })
        XCTAssertTrue(transport.tags.contains { $0.id.hasPrefix("tag-transport-") })
    }

    func testUsedPresetTagsSurviveCareerSwitch() {
        var medical = CareerPresets.apply(.medical, to: .makeDefault())
        let tagId = try? XCTUnwrap(medical.tags.first { $0.id.hasPrefix("tag-medical-") }?.id)
        medical.upsert(DayRecord(date: "2026-08-01", shiftId: ShiftID.day, hours: 8,
                                 tagIds: [tagId ?? ""], source: .manual))
        let transport = CareerPresets.apply(.transport, to: medical)
        XCTAssertTrue(transport.tags.contains { $0.id == tagId })
    }

    // MARK: - 改班次默认工时

    @MainActor
    func testChangingDefaultHoursUpdatesUntouchedRecords() throws {
        var document = ScheduleDocument.makeDefault()
        document.records = [
            DayRecord(date: "2026-09-02", shiftId: ShiftID.day, hours: 12, source: .cycle),
            DayRecord(date: "2026-09-03", shiftId: ShiftID.day, hours: 12, source: .cycle),
            // 这一天单独调过工时，改默认值不该动它
            DayRecord(date: "2026-09-04", shiftId: ShiftID.day, hours: 9, source: .manual),
        ]
        let store = ScheduleStore(fileURL: URL(fileURLWithPath: "/dev/null"), document: document)

        var day = try XCTUnwrap(document.shift(ShiftID.day))
        day.defaultHours = 11.5
        store.saveShift(day)

        XCTAssertEqual(store.document.record(on: "2026-09-02")?.hours, 11.5)
        XCTAssertEqual(store.document.record(on: "2026-09-03")?.hours, 11.5)
        XCTAssertEqual(store.document.record(on: "2026-09-04")?.hours, 9)
    }

    // MARK: - 班次时长

    func testCompactRangeMatchesTheWebVersion() {
        // 日历上显示的紧凑区间：8~20、20~8、16~24（结束的 00:00 写成 24）
        let day = ShiftDefinition(id: "s1", name: "白班", shortName: "白", color: AccentHex.yellow,
                                  startTime: "08:00", endTime: "20:00", defaultHours: 12)
        let night = ShiftDefinition(id: "s2", name: "夜班", shortName: "夜", color: AccentHex.blue,
                                    startTime: "20:00", endTime: "08:00", crossesMidnight: true,
                                    defaultHours: 12)
        let middle = ShiftDefinition(id: "s3", name: "中班", shortName: "中", color: AccentHex.cyan,
                                     startTime: "16:00", endTime: "00:00", defaultHours: 8)
        let half = ShiftDefinition(id: "s4", name: "半点班", shortName: "半", color: AccentHex.green,
                                   startTime: "08:30", endTime: "17:45", defaultHours: 9)
        XCTAssertEqual(day.compactRange, "8~20")
        XCTAssertEqual(night.compactRange, "20~8")
        XCTAssertEqual(middle.compactRange, "16~24")
        XCTAssertEqual(half.compactRange, "8.5~18")
    }

    func testCrossMidnightShiftDuration() {
        XCTAssertEqual(ShiftDefinition.duration(startTime: "20:00", endTime: "08:00", crossesMidnight: true), 12)
        XCTAssertEqual(ShiftDefinition.duration(startTime: "16:00", endTime: "00:00", crossesMidnight: false), 8)
    }
}
