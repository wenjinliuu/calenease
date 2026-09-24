import XCTest
@testable import CalenEase

/// 法定节假日判定，用例对应 web 版 `tests/holidays.test.ts`，
/// 另外补了农历节日的抽查，确保本机农历表与网页端 `lunar-typescript` 结论一致。
final class HolidayTests: XCTestCase {

    func testFixedDateHolidays() {
        XCTAssertEqual(Holidays.name(of: "2026-01-01"), "元旦")
        XCTAssertEqual(Holidays.name(of: "2026-05-01"), "劳动节")
        XCTAssertEqual(Holidays.name(of: "2026-10-01"), "国庆节")
        XCTAssertEqual(Holidays.name(of: "2026-10-03"), "国庆节")
    }

    func testOrdinaryDayHasNoHolidayLabel() {
        XCTAssertEqual(Holidays.name(of: "2026-08-08"), "")
    }

    func testShortNamesStayRecognizable() {
        XCTAssertEqual(Holidays.shortName("国庆节"), "国庆")
        XCTAssertEqual(Holidays.shortName("中秋节"), "中秋")
        XCTAssertEqual(Holidays.shortName("春节"), "春节")
    }

    func testLunarHolidaysMatchTheWebVersion() {
        // 2026 年春节是 2 月 17 日，除夕即 2 月 16 日。
        XCTAssertEqual(Holidays.name(of: "2026-02-16"), "除夕")
        XCTAssertEqual(Holidays.name(of: "2026-02-17"), "春节")
        XCTAssertEqual(Holidays.name(of: "2026-02-19"), "春节")
        XCTAssertEqual(Holidays.name(of: "2026-02-20"), "")
        // 端午与中秋
        XCTAssertEqual(Holidays.name(of: "2026-06-19"), "端午节")
        XCTAssertEqual(Holidays.name(of: "2026-09-25"), "中秋节")
        // 清明
        XCTAssertEqual(Holidays.name(of: "2026-04-05"), "清明节")
        XCTAssertEqual(Holidays.name(of: "2027-04-05"), "清明节")
    }

    func testKnownSpringFestivalDates() {
        XCTAssertEqual(Holidays.lunarNewYear(year: 2025), "2025-01-29")
        XCTAssertEqual(Holidays.lunarNewYear(year: 2026), "2026-02-17")
        XCTAssertEqual(Holidays.lunarNewYear(year: 2030), "2030-02-03")
    }
}
