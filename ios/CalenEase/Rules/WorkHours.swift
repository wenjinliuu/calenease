import Foundation

/// 基本工时推算与周期加班汇总，对应 web 版 page.tsx 里的
/// `estimateMonthlyTarget` / `getMonthlyTarget` / `getPeriodOvertime` 等一组函数。
enum WorkHours {

    /// 某月的预计基本工时：这个月的工作日 × 日标准工时。
    ///
    /// 工作日按国务院公布的放假与调休算——放假的日子不算，周末调休上班的日子算。
    /// 这一年还没有公布安排（也没下载到数据）时退回本地推算：周一至周五减去落在
    /// 工作日的法定节假日，不含调休。设置页另有逐月手动修正入口。
    static func estimateMonthlyTarget(year: Int,
                                      month: Int,
                                      dailyStandard: Double,
                                      holidays: HolidayCalendar = .shared) -> Double {
        let published = holidays.covers(year: year)
        var workdays = 0
        for day in 1...ScheduleCalendar.daysInMonth(year: year, month: month) {
            let key = ScheduleCalendar.key(year: year, month: month, day: day)
            let isWorkday = published
                ? holidays.isWorkday(key) ?? false
                : !ScheduleCalendar.isWeekend(key) && !Holidays.isHoliday(key)
            if isWorkday { workdays += 1 }
        }
        return Double(workdays) * dailyStandard
    }

    /// 某月的基本工时：有手动修正就用修正值。
    static func monthlyTarget(_ document: ScheduleDocument,
                              year: Int,
                              month: Int,
                              holidays: HolidayCalendar = .shared) -> Double {
        let key = ScheduleCalendar.monthKey(year: year, month: month)
        if let override = document.targets[key] { return override }
        // 综合计算工时的基本工时按法定的每日 8 小时算，不随个人日标准工时变化。
        let daily = document.work.system == .comprehensive ? 8 : document.work.dailyStandard
        return estimateMonthlyTarget(year: year, month: month, dailyStandard: daily, holidays: holidays)
    }

    static func monthlyTarget(_ document: ScheduleDocument, month: ReportingMonth) -> Double {
        monthlyTarget(document, year: month.year, month: month.month)
    }

    /// 包含指定月份的统计年度。只有综合计算工时才允许自定义年度起点。
    static func reportingCycle(for document: ScheduleDocument, year: Int, month: Int) -> AnnualCycle {
        AnnualCycle.containing(year: year,
                               month: month,
                               annualStartMonth: document.work.system == .comprehensive
                                   ? document.work.annualStartMonth : 1)
    }

    static func target(_ document: ScheduleDocument, months: [ReportingMonth]) -> Double {
        months.reduce(0) { $0 + monthlyTarget(document, month: $1) }
    }

    /// 计入工时的记录。休息、备班这类不计工作的班次一律排除。
    static func workRecords(_ document: ScheduleDocument, in records: [DayRecord]? = nil) -> [DayRecord] {
        (records ?? document.records).filter { document.shift($0.shiftId)?.countsAsWork == true }
    }

    /// 一段月份区间的加班合计。
    static func periodOvertime(_ document: ScheduleDocument,
                               records rawRecords: [DayRecord],
                               months: [ReportingMonth]) -> Double {
        let records = workRecords(document, in: rawRecords)
        let work = document.work

        if work.system == .custom && work.customRule == .monthly {
            return months.reduce(0) { sum, month in
                sum + OvertimeRules.overtime(records: records.filter { $0.monthKey == month.key },
                                             settings: work,
                                             standardTarget: 0)
            }
        }

        guard work.system == .comprehensive else {
            return OvertimeRules.overtime(records: records,
                                          settings: work,
                                          standardTarget: target(document, months: months))
        }

        switch work.period {
        case .month:
            return months.reduce(0) { sum, month in
                sum + OvertimeRules.overtime(records: records.filter { $0.monthKey == month.key },
                                             settings: work,
                                             standardTarget: monthlyTarget(document, month: month))
            }
        case .quarter, .halfYear:
            let size = work.period == .quarter ? 3 : 6
            var overtime: Double = 0
            var start = 0
            while start < months.count {
                let slice = Array(months[start..<min(start + size, months.count)])
                let keys = Set(slice.map(\.key))
                overtime += OvertimeRules.overtime(records: records.filter { keys.contains($0.monthKey) },
                                                   settings: work,
                                                   standardTarget: target(document, months: slice))
                start += size
            }
            return overtime
        case .week:
            return OvertimeRules.overtime(records: records, settings: weeklySettings(work), standardTarget: 0)
        case .year, .custom:
            return OvertimeRules.overtime(records: records,
                                          settings: work,
                                          standardTarget: target(document, months: months))
        }
    }

    /// 综合计算工时按周结算时借用的标准工时设置。
    static func weeklySettings(_ work: WorkSettings) -> WorkSettings {
        var settings = work
        settings.system = .standard
        settings.standardDailyEnabled = false
        settings.standardWeeklyEnabled = true
        return settings
    }

    /// 日历页顶部展示的加班：预计（整段周期）与实际（已完成部分）。
    struct OvertimeSummary: Equatable, Sendable {
        var label: String = ""
        var projected: Double = 0
        var actual: Double = 0
    }

    static func overtimeForCalendarMonth(_ document: ScheduleDocument,
                                         year: Int,
                                         month: Int,
                                         today: String) -> OvertimeSummary {
        guard document.work.trackHours, document.work.trackOvertime else { return OvertimeSummary() }

        if document.work.system == .comprehensive {
            return comprehensiveScope(document, year: year, month: month, today: today)
        }
        let monthKey = ScheduleCalendar.monthKey(year: year, month: month)
        let monthRecords = workRecords(document).filter { $0.monthKey == monthKey }
        let target = monthlyTarget(document, year: year, month: month)
        return OvertimeSummary(
            label: "\(month + 1)月",
            projected: OvertimeRules.overtime(records: monthRecords, settings: document.work, standardTarget: target),
            actual: OvertimeRules.overtime(records: monthRecords.filter { $0.countsAsCompleted(today: today) },
                                           settings: document.work, standardTarget: target)
        )
    }

    /// 综合计算工时下，这个月归属的结算范围（月 / 季度 / 半年 / 年 / 周）。
    static func comprehensiveScope(_ document: ScheduleDocument,
                                   year: Int,
                                   month: Int,
                                   today: String) -> OvertimeSummary {
        let cycle = reportingCycle(for: document, year: year, month: month)
        let activeIndex = cycle.months.firstIndex { $0.year == year && $0.month == month } ?? 0

        if document.work.period == .week {
            let monthKey = ScheduleCalendar.monthKey(year: year, month: month)
            let monthRecords = workRecords(document).filter { $0.monthKey == monthKey }
            let settings = weeklySettings(document.work)
            return OvertimeSummary(
                label: "\(month + 1)月各周",
                projected: OvertimeRules.overtime(records: monthRecords, settings: settings, standardTarget: 0),
                actual: OvertimeRules.overtime(records: monthRecords.filter { $0.countsAsCompleted(today: today) },
                                               settings: settings, standardTarget: 0)
            )
        }

        var scopeMonths = [cycle.months[activeIndex]]
        var label = "\(month + 1)月"
        switch document.work.period {
        case .quarter:
            let start = (activeIndex / 3) * 3
            scopeMonths = Array(cycle.months[start..<min(start + 3, cycle.months.count)])
            label = "第 \(activeIndex / 3 + 1) 季度"
        case .halfYear:
            let start = activeIndex < 6 ? 0 : 6
            scopeMonths = Array(cycle.months[start..<min(start + 6, cycle.months.count)])
            label = start == 0 ? "上半年" : "下半年"
        case .year:
            scopeMonths = cycle.months
            label = cycle.label
        case .custom:
            scopeMonths = cycle.months
            label = "\(cycle.label)自定义周期"
        default:
            break
        }

        let keys = Set(scopeMonths.map(\.key))
        let scoped = workRecords(document).filter { keys.contains($0.monthKey) }
        let target = target(document, months: scopeMonths)
        return OvertimeSummary(
            label: label,
            projected: OvertimeRules.overtime(records: scoped, settings: document.work, standardTarget: target),
            actual: OvertimeRules.overtime(records: scoped.filter { $0.countsAsCompleted(today: today) },
                                           settings: document.work, standardTarget: target)
        )
    }

    /// 加班能否按月拆开展示。综合计算工时按季度以上结算时就不能。
    static func canAllocateByMonth(_ document: ScheduleDocument) -> Bool {
        document.work.trackOvertime
            && (document.work.system != .comprehensive
                || document.work.period == .month
                || document.work.period == .week)
    }
}
