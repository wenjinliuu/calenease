import XCTest
@testable import ShiftLedger

/// 放假安排、系统农历与节日。
final class HolidayCalendarTests: XCTestCase {

    /// 2026 年 9、10 月的实际安排（摘自 holidays/v1/2026.json）。
    private let autumn2026 = HolidayYearFile(schemaVersion: 1, year: 2026, days: [
        .init(date: "2026-09-20", name: "国庆节", type: .work),
        .init(date: "2026-09-25", name: "中秋节", type: .off),
        .init(date: "2026-09-26", name: "中秋节", type: .off),
        .init(date: "2026-09-27", name: "中秋节", type: .off),
        .init(date: "2026-10-01", name: "国庆节", type: .off),
        .init(date: "2026-10-02", name: "国庆节", type: .off),
        .init(date: "2026-10-03", name: "国庆节", type: .off),
        .init(date: "2026-10-04", name: "国庆节", type: .off),
        .init(date: "2026-10-05", name: "国庆节", type: .off),
        .init(date: "2026-10-06", name: "国庆节", type: .off),
        .init(date: "2026-10-07", name: "国庆节", type: .off),
        .init(date: "2026-10-10", name: "国庆节", type: .work),
    ])

    // MARK: - 放假安排

    func testEmptyYearFileDoesNotCountAsPublished() {
        // 还没公布的年份源仓库先放一个空文件，不能当成「一天假都没有」。
        let calendar = HolidayCalendar(files: [autumn2026,
                                               HolidayYearFile(schemaVersion: 1, year: 2027, days: [])])
        XCTAssertTrue(calendar.covers(year: 2026))
        XCTAssertFalse(calendar.covers(year: 2027))
        XCTAssertNil(calendar.isWorkday("2027-03-01"))
    }

    func testAdjustedDaysOverrideTheWeekend() {
        let calendar = HolidayCalendar(files: [autumn2026])
        XCTAssertEqual(calendar.adjustment(on: "2026-09-20"), .work)
        XCTAssertEqual(calendar.isWorkday("2026-09-20"), true)   // 周日调休上班
        XCTAssertEqual(calendar.isWorkday("2026-10-05"), false)  // 周一放假
        XCTAssertEqual(calendar.isWorkday("2026-09-24"), true)   // 普通周四
        XCTAssertEqual(calendar.isWorkday("2026-09-19"), false)  // 普通周六
    }

    func testBasicHoursFollowThePublishedSchedule() {
        let calendar = HolidayCalendar(files: [autumn2026])
        // 9 月：22 个周一至周五，9/25（周五）放假，9/20（周日）补班 → 22 天。
        XCTAssertEqual(WorkHours.estimateMonthlyTarget(year: 2026, month: 8, dailyStandard: 8, holidays: calendar), 176)
        // 10 月：22 个周一至周五，1、2、5、6、7 日放假，10/10（周六）补班 → 18 天。
        XCTAssertEqual(WorkHours.estimateMonthlyTarget(year: 2026, month: 9, dailyStandard: 8, holidays: calendar), 144)
    }

    func testBasicHoursFallBackToTheLocalRuleForUnpublishedYears() {
        let calendar = HolidayCalendar(files: [autumn2026])
        XCTAssertEqual(WorkHours.estimateMonthlyTarget(year: 2027, month: 9, dailyStandard: 8, holidays: calendar),
                       WorkHours.estimateMonthlyTarget(year: 2027, month: 9, dailyStandard: 8, holidays: .empty))
    }

    func testBundledSnapshotLoads() {
        let snapshot = HolidayData.loadLocal()
        let calendar = snapshot.calendar
        XCTAssertTrue(calendar.covers(year: 2026), "包里应当带着 holidays/v1 快照")
        XCTAssertEqual(calendar.adjustment(on: "2026-10-01"), .off)
        XCTAssertEqual(calendar.adjustment(on: "2026-09-20"), .work)
        XCTAssertEqual(snapshot.hashes[2026]?.count, 64)
    }

    func testSHA256MatchesThePublishedFormat() {
        XCTAssertEqual(HolidayData.sha256(Data()),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    }

    // MARK: - 节日：只在当天

    func testStatutoryFestivalsOnlyOnTheDayItself() {
        XCTAssertEqual(Festivals.festival(on: "2026-10-01")?.shortName, "国庆")
        XCTAssertNil(Festivals.festival(on: "2026-10-02"))
        XCTAssertNil(Festivals.festival(on: "2026-10-03"))
        XCTAssertEqual(Festivals.festival(on: "2026-01-01")?.shortName, "元旦")
        XCTAssertEqual(Festivals.festival(on: "2026-05-01")?.shortName, "劳动")
        XCTAssertNil(Festivals.festival(on: "2026-05-02"))
        XCTAssertEqual(Festivals.festival(on: "2026-04-05")?.shortName, "清明")
    }

    func testLunarFestivalsComeFromTheSystemCalendar() {
        XCTAssertEqual(Festivals.festival(on: "2026-02-16")?.shortName, "除夕")
        XCTAssertEqual(Festivals.festival(on: "2026-02-17")?.shortName, "春节")
        XCTAssertNil(Festivals.festival(on: "2026-02-18"))
        XCTAssertEqual(Festivals.festival(on: "2026-06-19")?.shortName, "端午")
        XCTAssertEqual(Festivals.festival(on: "2026-09-25")?.shortName, "中秋")
        XCTAssertEqual(Festivals.festival(on: "2026-09-25")?.kind, .statutory)
        // 2020 年国庆和中秋同一天，写中秋。
        XCTAssertEqual(Festivals.festival(on: "2020-10-01")?.shortName, "中秋")
    }

    func testTraditionalFestivalsAreMarkedAsSuch() {
        let lantern = Festivals.festival(on: "2026-03-03")
        XCTAssertEqual(lantern?.shortName, "元宵")
        XCTAssertEqual(lantern?.kind, .traditional)
    }

    // MARK: - 农历

    func testLunarTextShowsTheMonthOnTheFirstDay() {
        XCTAssertEqual(LunarCalendar.text(for: "2026-02-17"), "正月")
        XCTAssertEqual(LunarCalendar.text(for: "2026-02-18"), "初二")
        XCTAssertEqual(LunarCalendar.text(for: "2026-09-11"), "八月")
        XCTAssertEqual(LunarCalendar.text(for: "2026-09-25"), "十五")
    }

    // MARK: - 设置

    func testOldDisplaySettingsDecodeWithLunarOff() throws {
        let json = #"{"showShift":true,"showTags":false,"showShiftTime":true,"showHours":true,"showHolidays":true}"#
        let display = try JSONDecoder().decode(CalendarDisplaySettings.self, from: Data(json.utf8))
        XCTAssertFalse(display.showLunar)
        XCTAssertFalse(display.showTags)
        XCTAssertTrue(display.showHolidays)
    }
}
