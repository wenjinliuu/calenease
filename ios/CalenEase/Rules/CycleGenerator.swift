import Foundation

/// 循环排班的生成规则，对应 web 版 `generateCycleRecords` / `materializeCycleYear`。
///
/// 循环保存的是班次 ID 序列，某一天排哪个班只看它距循环起始日的天数，
/// 所以单日改写不会打断后面的循环。
enum CycleGenerator {

    /// 生成 [startDate, endDate] 区间内的循环记录。早于循环起始日的部分自动跳过。
    static func records(cycle: ActiveCycle,
                        shifts: [ShiftDefinition],
                        from startDate: String,
                        to endDate: String) -> [DayRecord] {
        guard !cycle.shiftIds.isEmpty else { return [] }
        let shiftMap = Dictionary(uniqueKeysWithValues: shifts.map { ($0.id, $0) })
        let begin = max(startDate, cycle.startDate)
        guard begin <= endDate else { return [] }

        return ScheduleCalendar.range(begin, endDate).compactMap { date in
            let shiftId = shiftId(for: date, cycle: cycle)
            guard let shift = shiftMap[shiftId] else { return nil }
            return DayRecord(date: date,
                             shiftId: shiftId,
                             hours: shift.defaultHours,
                             completed: false,
                             planned: true,
                             source: .cycle,
                             cycleId: cycle.id)
        }
    }

    /// 某一天在循环里落到第几个班次。
    static func shiftId(for date: String, cycle: ActiveCycle) -> String {
        let length = cycle.shiftIds.count
        guard length > 0 else { return "" }
        let offset = ScheduleCalendar.dayDifference(date, cycle.startDate)
        let index = ((offset % length) + length) % length
        return cycle.shiftIds[index]
    }

    /// 把某一年的循环记录落到数据里。已有的手动记录保持不动。
    static func materialize(_ document: ScheduleDocument, year: Int) -> ScheduleDocument {
        guard let cycle = document.activeCycle,
              (Int(cycle.startDate.prefix(4)) ?? 0) <= year
        else { return document }

        let generated = records(cycle: cycle,
                                shifts: document.shifts,
                                from: max(ScheduleCalendar.key(year: year, month: 0, day: 1), cycle.startDate),
                                to: ScheduleCalendar.key(year: year, month: 11, day: 31))
        var merged = Dictionary(uniqueKeysWithValues: document.records.map { ($0.date, $0) })
        for record in generated {
            let current = merged[record.date]
            if current == nil || current?.source == .cycle {
                // 同一个循环已经生成过的日子保留原样，避免覆盖掉已确认状态。
                if let current, current.source == .cycle, current.cycleId == cycle.id { continue }
                merged[record.date] = record
            }
        }
        var next = document
        next.records = merged.values.sorted { $0.date < $1.date }
        return next
    }

    /// 换一套循环：起始日之前的记录全部保留，之后按新循环重排到 `throughYear` 年底。
    static func replace(_ document: ScheduleDocument,
                        with cycle: ActiveCycle,
                        throughYear: Int) -> ScheduleDocument {
        var next = document
        let kept = document.records.filter { $0.date < cycle.startDate }
        let generated = records(cycle: cycle,
                                shifts: document.shifts,
                                from: cycle.startDate,
                                to: ScheduleCalendar.key(year: throughYear, month: 11, day: 31))
        next.activeCycle = cycle
        next.records = (kept + generated).sorted { $0.date < $1.date }
        return next
    }

    /// 把当前统计年度覆盖到的年份都生成出来（跨年度周期会涉及两个自然年）。
    static func materializeReportingYears(_ document: ScheduleDocument,
                                          year: Int,
                                          month: Int) -> ScheduleDocument {
        let cycle = WorkHours.reportingCycle(for: document, year: year, month: month)
        return Set([cycle.startYear, cycle.endYear]).sorted().reduce(document) { current, cycleYear in
            materialize(current, year: cycleYear)
        }
    }
}
