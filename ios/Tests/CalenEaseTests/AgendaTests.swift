import XCTest
@testable import CalenEase

/// 日程重复、倒数日、提醒排程。
final class AgendaTests: XCTestCase {

    private func day(_ key: String) -> Int { DayNumber.of(key)! }

    // MARK: - 天序号

    func testDayNumberRoundTrip() {
        XCTAssertEqual(DayNumber.of("1970-01-01"), 0)
        XCTAssertEqual(DayNumber.of("2000-03-01"), 11017)
        XCTAssertEqual(DayNumber.key(day("2024-02-29")), "2024-02-29")
        // 1970-01-01 是周四，周一 = 0
        XCTAssertEqual(DayNumber.weekday(0), 3)
        XCTAssertEqual(DayNumber.weekday(day("2026-09-21")), 0)
        XCTAssertNil(DayNumber.of("2026-9-1"))
    }

    // MARK: - 重复

    func testWeeklyRecurrenceAndExceptions() {
        var event = CalendarEvent(title: "健身", startDate: "2026-09-01")   // 周二
        event.recurrence.kind = .weekly
        event.recurrence.weekdays = [1, 3]                                  // 周二、周四
        event.exceptions = ["2026-09-03"]
        let hits = EventEngine.occurrences(of: [event], from: day("2026-09-01"), to: day("2026-09-10"))
            .map(\.startKey)
        XCTAssertEqual(hits, ["2026-09-01", "2026-09-08", "2026-09-10"])
    }

    func testMonthlyYearlyIntervalAndUntil() {
        var monthly = CalendarEvent(title: "还款", startDate: "2026-01-31")
        monthly.recurrence.kind = .monthly
        let months = EventEngine.occurrences(of: [monthly], from: day("2026-01-01"), to: day("2026-05-31"))
        // 没有 31 号的月份跳过
        XCTAssertEqual(months.map(\.startKey), ["2026-01-31", "2026-03-31", "2026-05-31"])

        var yearly = CalendarEvent(title: "生日", startDate: "2020-06-15", isAllDay: true)
        yearly.recurrence.kind = .yearly
        XCTAssertEqual(EventEngine.occurrences(of: [yearly], from: day("2026-06-01"), to: day("2026-06-30")).count, 1)

        var interval = CalendarEvent(title: "浇花", startDate: "2026-09-01")
        interval.recurrence.kind = .interval
        interval.recurrence.interval = 3
        interval.recurrence.until = "2026-09-08"
        let every3 = EventEngine.occurrences(of: [interval], from: day("2026-08-01"), to: day("2026-09-30"))
        XCTAssertEqual(every3.map(\.startKey), ["2026-09-01", "2026-09-04", "2026-09-07"])
    }

    func testMultiDayEventReachesIntoWindow() {
        let trip = CalendarEvent(title: "出差", startDate: "2026-09-28", endDate: "2026-10-02", isAllDay: true)
        let october = EventEngine.occurrences(of: [trip], from: day("2026-10-01"), to: day("2026-10-31"))
        XCTAssertEqual(october.count, 1)
        XCTAssertTrue(october[0].isMultiDay)
        XCTAssertEqual(EventEngine.occurrences(of: [trip], on: "2026-10-02").count, 1)
        XCTAssertEqual(EventEngine.occurrences(of: [trip], on: "2026-10-03").count, 0)
    }

    func testShiftFollowingEventWithOffset() {
        var event = CalendarEvent(title: "补觉", startDate: "2026-09-01", isAllDay: true)
        event.recurrence.kind = .shift
        event.recurrence.shiftId = "night"
        event.recurrence.shiftOffset = 1
        let shiftDays = ["2026-09-02": "night", "2026-09-03": "day", "2026-09-05": "night"]
        let hits = EventEngine.occurrences(of: [event], from: day("2026-09-01"), to: day("2026-09-10"),
                                           shiftDays: shiftDays)
        XCTAssertEqual(hits.map(\.startKey), ["2026-09-03", "2026-09-06"])
    }

    // MARK: - 周视图色条

    func testWeekLayoutAssignsLanesAndCountsOverflow() {
        let weekStart = day("2026-09-21")   // 周一
        let long = EventOccurrence(event: CalendarEvent(title: "长", startDate: "2026-09-21"),
                                   start: weekStart, end: weekStart + 3)
        let a = EventOccurrence(event: CalendarEvent(title: "a", startDate: "2026-09-22"),
                                start: weekStart + 1, end: weekStart + 1)
        let b = EventOccurrence(event: CalendarEvent(title: "b", startDate: "2026-09-22"),
                                start: weekStart + 1, end: weekStart + 1)
        let later = EventOccurrence(event: CalendarEvent(title: "c", startDate: "2026-09-26"),
                                    start: weekStart + 5, end: weekStart + 5)
        let result = EventEngine.layoutWeek([b, later, long, a], weekStart: weekStart,
                                            visibleColumns: 0...6, lanes: 2)
        let lanes = Dictionary(uniqueKeysWithValues: result.segments.map { ($0.occurrence.event.title, $0.lane) })
        XCTAssertEqual(lanes["长"], 0)
        XCTAssertEqual(result.segments.first { $0.occurrence.event.title == "长" }?.span, 4)
        XCTAssertEqual(lanes["c"], 0)
        // 周二有三条，只放得下两条，收起一条
        XCTAssertEqual(result.hidden[1], 1)
        XCTAssertEqual(result.segments.count, 3)
    }

    func testWeekLayoutClipsToVisibleColumns() {
        let weekStart = day("2026-09-28")
        let trip = EventOccurrence(event: CalendarEvent(title: "出差", startDate: "2026-09-28"),
                                   start: weekStart, end: weekStart + 4)
        // 10 月 1 日是这一周的第 4 列（下标 3），网格上只画 10 月那几列
        let result = EventEngine.layoutWeek([trip], weekStart: weekStart, visibleColumns: 3...6, lanes: 2)
        XCTAssertEqual(result.segments.first?.column, 3)
        XCTAssertEqual(result.segments.first?.span, 2)
        XCTAssertEqual(result.segments.first?.startsHere, false)
    }

    // MARK: - 倒数日

    func testCountdownAndCountUp() {
        let exam = Countdown(title: "考试", date: "2026-10-01")
        let status = CountdownMath.status(of: exam, today: "2026-09-23")
        XCTAssertEqual(status?.days, 8)
        XCTAssertEqual(status?.caption, "还有")

        let birthday = Countdown(title: "生日", date: "1996-02-29", repeatsYearly: true)
        // 平年落在 2 月 28 日
        XCTAssertEqual(CountdownMath.status(of: birthday, today: "2027-01-01")?.targetDate, "2027-02-28")
        XCTAssertEqual(CountdownMath.status(of: birthday, today: "2028-02-29")?.isToday, true)

        let job = Countdown(title: "入职", date: "2025-06-20", kind: .countUp)
        let up = CountdownMath.status(of: job, today: "2026-09-23")
        XCTAssertEqual(up?.caption, "已经")
        XCTAssertEqual(up?.days, 460)
        XCTAssertEqual(up?.breakdown, "1 年 3 个月 3 天")
    }

    func testBreakdownBorrowsFromPreviousMonth() {
        XCTAssertEqual(CountdownMath.breakdown(from: day("2026-01-31"), to: day("2026-03-01")), "1 个月 1 天")
        XCTAssertEqual(CountdownMath.breakdown(from: day("2026-09-23"), to: day("2026-09-23")), "0 天")
    }

    // MARK: - 提醒

    func testReminderPlannerCoversShiftsEventsAndCountdowns() throws {
        var document = ScheduleDocument.makeDefault()
        let shift = try XCTUnwrap(document.orderedShifts.first { !$0.isRest && $0.countsAsWork && !$0.startTime.isEmpty })
        document.records = [DayRecord(date: "2026-09-24", shiftId: shift.id, hours: shift.defaultHours)]
        document.reminders.shiftStartEnabled = true
        document.reminders.shiftStartMinutes = 60
        document.reminders.clockOutEnabled = true
        document.events = [CalendarEvent(title: "体检", startDate: "2026-09-25",
                                         startTime: "08:30", endTime: "09:30", reminderMinutes: 15)]
        document.countdowns = [Countdown(title: "国庆", date: "2026-10-01")]

        let calendar = ScheduleCalendar.calendar
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 9, day: 23, hour: 12)))
        let plan = ReminderPlanner.plan(document, now: now)
        let ids = plan.map(\.id)
        XCTAssertTrue(ids.contains("shift-start-2026-09-24"))
        XCTAssertTrue(ids.contains("clock-out-2026-09-24"))
        XCTAssertTrue(ids.contains { $0.hasPrefix("event-") })
        XCTAssertTrue(ids.contains("countdown-\(document.countdowns[0].id)-2026-10-01"))
        XCTAssertEqual(plan.map(\.fireDate), plan.map(\.fireDate).sorted())

        let event = try XCTUnwrap(plan.first { $0.id.hasPrefix("event-") })
        let parts = calendar.dateComponents([.day, .hour, .minute], from: event.fireDate)
        XCTAssertEqual(parts.day, 25)
        XCTAssertEqual(parts.hour, 8)
        XCTAssertEqual(parts.minute, 15)

        // 关掉排班功能，班次提醒全部不排
        document.features.shiftsEnabled = false
        XCTAssertFalse(ReminderPlanner.plan(document, now: now).contains { $0.id.hasPrefix("shift-") })
    }

    // MARK: - 老文件

    func testOldFileWithoutAgendaFieldsStillDecodes() throws {
        var raw = try XCTUnwrap(JSONSerialization.jsonObject(
            with: JSONEncoder().encode(ScheduleDocument.makeDefault())) as? [String: Any])
        for key in ["events", "countdowns", "reminders", "features"] { raw.removeValue(forKey: key) }
        var display = try XCTUnwrap(raw["display"] as? [String: Any])
        display.removeValue(forKey: "eventSlots")
        raw["display"] = display
        let data = try JSONSerialization.data(withJSONObject: raw)
        let decoded = try JSONDecoder().decode(ScheduleDocument.self, from: data)
        XCTAssertTrue(decoded.events.isEmpty)
        XCTAssertTrue(decoded.features.shiftsEnabled)
        XCTAssertEqual(decoded.display.eventSlots, 2)
        XCTAssertEqual(decoded.reminders, ReminderSettings())
    }

    func testBackupRoundTripKeepsAgenda() throws {
        var document = ScheduleDocument.makeDefault()
        var event = CalendarEvent(title: "值班会", startDate: "2026-09-01")
        event.recurrence.kind = .weekly
        event.recurrence.weekdays = [0]
        document.events = [event]
        document.countdowns = [Countdown(title: "入职", date: "2025-06-20", kind: .countUp)]
        document.features.shiftsEnabled = false
        let raw = try JSONSerialization.jsonObject(with: JSONEncoder().encode(document))
        let restored = DocumentNormalizer.document(fromBackup: raw)
        XCTAssertEqual(restored.events, document.events)
        XCTAssertEqual(restored.countdowns, document.countdowns)
        XCTAssertFalse(restored.features.shiftsEnabled)
    }

    // MARK: - 这一轮新增

    func testEventWithoutNewFieldsStillDecodes() throws {
        let json = """
        {"id":"event-1","title":"开会","startDate":"2026-09-24","endDate":"2026-09-24","isAllDay":false,
         "startTime":"09:00","endTime":"10:00","color":"#32ADE6",
         "recurrence":{"kind":"none","weekdays":[],"interval":2,"shiftOffset":0},"exceptions":[]}
        """
        let event = try JSONDecoder().decode(CalendarEvent.self, from: Data(json.utf8))
        XCTAssertEqual(event.title, "开会")
        XCTAssertNil(event.location)
        XCTAssertTrue(event.completions.isEmpty)
    }

    func testTurningOffDefaultReminderSurvivesARoundTrip() throws {
        var settings = ReminderSettings()
        settings.eventDefaultMinutes = nil
        let data = try JSONEncoder().encode(settings)
        XCTAssertNil(try JSONDecoder().decode(ReminderSettings.self, from: data).eventDefaultMinutes)
        // 老文件里没有这个键，才用默认的 15 分钟
        XCTAssertEqual(try JSONDecoder().decode(ReminderSettings.self, from: Data("{}".utf8)).eventDefaultMinutes, 15)
    }

    func testCompletionToggleIsPerOccurrence() {
        var event = CalendarEvent(title: "吃药", startDate: "2026-09-01")
        event.recurrence.kind = .daily
        event.completions = ["2026-09-02"]
        let hits = EventEngine.occurrences(of: [event], from: day("2026-09-01"), to: day("2026-09-03"))
        XCTAssertEqual(hits.map(\.isCompleted), [false, true, false])
    }

    func testTrendChartInsertsCrossingPoints() {
        let points = [
            HoursTrendChart.Point(index: 0, label: "1月", basic: 160, planned: 180),
            HoursTrendChart.Point(index: 1, label: "2月", basic: 160, planned: 140),
            HoursTrendChart.Point(index: 3, label: "4月", basic: 160, planned: 170),
        ]
        let areas = HoursTrendChart.areaPoints(points)
        // 1 月到 2 月之间正好在中点穿过基本线；2 月和 4 月之间隔了没排班的 3 月，断开不连
        XCTAssertEqual(areas.count, 4)
        XCTAssertEqual(areas[1].x, 0.5, accuracy: 0.0001)
        XCTAssertEqual(areas[1].planned, areas[1].basic)
        XCTAssertEqual(areas.map(\.segment), [0, 0, 0, 1])
    }
}
