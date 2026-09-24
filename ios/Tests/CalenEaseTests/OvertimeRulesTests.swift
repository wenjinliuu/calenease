import XCTest
@testable import CalenEase

/// 加班判定的一致性测试，对应 web 版 `tests/schedule.test.ts` 里的加班用例。
final class OvertimeRulesTests: XCTestCase {

    private func record(_ date: String, hours: Double, manualOvertime: Double? = nil) -> DayRecord {
        DayRecord(date: date, shiftId: ShiftID.day, hours: hours,
                  manualOvertime: manualOvertime, source: .manual)
    }

    func testStandardSystemCountsHoursBeyondDailyLimit() {
        var settings = WorkSettings()
        settings.system = .standard
        settings.standardWeeklyEnabled = false
        settings.dailyStandard = 8

        let overtime = OvertimeRules.overtime(records: [record("2026-08-01", hours: 10)],
                                              settings: settings, standardTarget: 8)
        XCTAssertEqual(overtime, 2)
    }

    func testComprehensiveSystemDoesNotJudgeSingleLongDay() {
        var settings = WorkSettings()
        settings.system = .comprehensive

        // 综合计算工时不看单日长短，只看整段周期的总量对不对得上基本工时。
        // 一天 12 小时离 168 还差得远，所以这里是个负数，不是加班。
        let overtime = OvertimeRules.overtime(records: [record("2026-08-01", hours: 12)],
                                              settings: settings, standardTarget: 168)
        XCTAssertEqual(overtime, 12 - 168)
    }

    func testComprehensiveOvertimeGoesNegativeWhenShortOfTarget() {
        var settings = WorkSettings()
        settings.system = .comprehensive
        let records = (1...10).map { record(String(format: "2026-08-%02d", $0), hours: 8) }

        // 上了 80，基本工时 96，差 16——额外工时就是 −16，不再夹到 0。
        // 这样统计页那四张卡才对得上：计划工时 − 基本工时 = 额外工时。
        XCTAssertEqual(OvertimeRules.overtime(records: records, settings: settings, standardTarget: 96), -16)
    }

    func testDisablingOvertimeAlwaysReturnsZero() {
        var settings = WorkSettings()
        settings.trackOvertime = false

        let overtime = OvertimeRules.overtime(records: [record("2026-08-01", hours: 20)],
                                              settings: settings, standardTarget: 0)
        XCTAssertEqual(overtime, 0)
    }

    func testStandardSystemTakesTheLargerOfDailyAndWeekly() {
        var settings = WorkSettings()
        settings.system = .standard
        settings.dailyStandard = 8
        settings.weeklyStandard = 40
        // 同一周（2026-08-03 是周一）连上六天 9 小时：
        // 日口径 6×1=6，周口径 54−40=14，取大的 14。
        let records = (3...8).map { record(String(format: "2026-08-%02d", $0), hours: 9) }

        let overtime = OvertimeRules.overtime(records: records, settings: settings, standardTarget: 0)
        XCTAssertEqual(overtime, 14)
    }

    func testIrregularSystemOnlyCountsManualOvertime() {
        var settings = WorkSettings()
        settings.system = .irregular

        let records = [record("2026-08-01", hours: 14, manualOvertime: 3),
                       record("2026-08-02", hours: 14)]
        XCTAssertEqual(OvertimeRules.overtime(records: records, settings: settings, standardTarget: 0), 3)
    }

    func testHourlySystemDoesNotJudgeOvertimeAutomatically() {
        var settings = WorkSettings()
        settings.system = .hourly

        let records = [record("2026-08-01", hours: 12), record("2026-08-02", hours: 10, manualOvertime: 1)]
        XCTAssertEqual(OvertimeRules.overtime(records: records, settings: settings, standardTarget: 0), 1)
        XCTAssertEqual(WorkSystem(rawValue: "hourly"), .hourly)
    }

    func testCustomDailyRuleUsesItsOwnThreshold() {
        var settings = WorkSettings()
        settings.system = .custom
        settings.customRule = .daily
        settings.customThreshold = 10

        let records = [record("2026-08-01", hours: 12), record("2026-08-02", hours: 9)]
        XCTAssertEqual(OvertimeRules.overtime(records: records, settings: settings, standardTarget: 0), 2)
    }

    func testCustomPeriodRuleComparesAgainstTotal() {
        var settings = WorkSettings()
        settings.system = .custom
        settings.customRule = .period
        settings.customThreshold = 20

        let records = [record("2026-08-01", hours: 12), record("2026-08-02", hours: 12)]
        XCTAssertEqual(OvertimeRules.overtime(records: records, settings: settings, standardTarget: 0), 4)
    }

    // MARK: - 基本工时推算

    func testMonthlyTargetSubtractsWeekdayHolidays() {
        // 2026 年 10 月：22 个工作日，其中 10/1（周四）、10/2（周五）是法定节假日，
        // 10/3 落在周六本来就不计。按 8 小时算即 (22−2)×8 = 160。
        let estimate = WorkHours.estimateMonthlyTarget(year: 2026, month: 9, dailyStandard: 8)
        XCTAssertEqual(estimate, 160)
    }

    func testManualTargetOverridesEstimate() {
        var document = ScheduleDocument.makeDefault()
        document.targets["2026-10"] = 152
        XCTAssertEqual(WorkHours.monthlyTarget(document, year: 2026, month: 9), 152)
    }

    /// 用户实测的口径：2026 年 9 月基本工时 168，排 20 个班、每班 11.5 小时，
    /// 总工时 230，加班应当是 62 而不是按旧默认值算出来的 72。
    func testComprehensiveOvertimeUsesTheShiftsCurrentHours() {
        var document = ScheduleDocument.makeDefault()
        document.work.system = .comprehensive
        document.work.period = .month

        let workdays = [2, 3, 4, 5, 8, 9, 10, 11, 14, 15, 16, 17, 20, 21, 22, 23, 26, 27, 28, 29]
        document.records = workdays.map {
            DayRecord(date: String(format: "2026-09-%02d", $0), shiftId: ShiftID.day,
                      hours: 11.5, source: .cycle)
        }

        let months = [ReportingMonth(year: 2026, month: 8)]
        XCTAssertEqual(WorkHours.target(document, months: months), 168)
        XCTAssertEqual(document.records.reduce(0) { $0 + $1.hours }, 230)
        XCTAssertEqual(WorkHours.periodOvertime(document, records: document.records, months: months), 62)
    }

    func testRestRecordsNeverCountTowardHours() {
        var document = ScheduleDocument.makeDefault()
        document.work.system = .comprehensive
        document.records = [
            DayRecord(date: "2026-09-02", shiftId: ShiftID.day, hours: 12, source: .cycle),
            // 休息日即使误填了工时也不该进统计
            DayRecord(date: "2026-09-03", shiftId: ShiftID.rest, hours: 8, source: .cycle),
        ]
        XCTAssertEqual(WorkHours.workRecords(document).count, 1)
    }

    func testMonthlyOvertimeUsesEachMonthsOwnTarget() {
        var document = ScheduleDocument.makeDefault()
        document.work.system = .comprehensive
        document.work.period = .month
        document.targets["2026-01"] = 100
        document.targets["2026-02"] = 100
        document.records = [DayRecord(date: "2026-01-15", shiftId: ShiftID.day, hours: 120, source: .manual),
                            DayRecord(date: "2026-02-15", shiftId: ShiftID.day, hours: 90, source: .manual)]

        let months = [ReportingMonth(year: 2026, month: 0), ReportingMonth(year: 2026, month: 1)]
        // 一月超 20 小时、二月差 10 小时，逐月结算之后相抵，合计 10。
        XCTAssertEqual(WorkHours.periodOvertime(document, records: document.records, months: months), 10)
    }
}
