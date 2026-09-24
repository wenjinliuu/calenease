import Foundation

/// 日程的一次发生。重复日程每重复一次就是一个 occurrence。
struct EventOccurrence: Hashable, Identifiable, Sendable {
    let event: CalendarEvent
    /// 这一次的开始、结束日期（天序号，含结束那天）。
    let start: Int
    let end: Int

    var id: String { "\(event.id)@\(start)" }
    var startKey: String { DayNumber.key(start) }
    var isMultiDay: Bool { end > start }
    var isCompleted: Bool { event.completions.contains(startKey) }

    /// 同一天里排列的先后：全天的在前，其余按开始时间。
    static func dayOrder(_ lhs: EventOccurrence, _ rhs: EventOccurrence) -> Bool {
        if lhs.event.isAllDay != rhs.event.isAllDay { return lhs.event.isAllDay }
        if lhs.start != rhs.start { return lhs.start < rhs.start }
        if lhs.event.startTime != rhs.event.startTime { return lhs.event.startTime < rhs.event.startTime }
        return lhs.event.title < rhs.event.title
    }
}

/// 周视图里一条色条：从第几列开始、横跨几列、排在第几道。
struct EventBarSegment: Hashable, Identifiable, Sendable {
    let occurrence: EventOccurrence
    /// 在这一周里的列，周一 = 0。
    let column: Int
    let span: Int
    let lane: Int
    /// 色条左端是不是这次日程真正的开始（跨周接续的就不是，左边不画圆角提示）。
    let startsHere: Bool

    var id: String { "\(occurrence.id)#\(column)" }
}

enum EventEngine {

    /// 某段日期（天序号，闭区间）里所有日程的发生情况。
    ///
    /// `shiftDays` 是「日期 → 班次 ID」，给「跟随班次」的日程用；调用方建一次、反复用。
    static func occurrences(of events: [CalendarEvent],
                            from first: Int,
                            to last: Int,
                            shiftDays: [String: String] = [:]) -> [EventOccurrence] {
        var result: [EventOccurrence] = []
        for event in events {
            guard let origin = DayNumber.of(event.startDate) else { continue }
            let span = event.spanDays
            let until = event.recurrence.until.flatMap(DayNumber.of) ?? Int.max
            let exceptions = Set(event.exceptions.compactMap(DayNumber.of))
            // 开始在窗口之前、但跨进窗口里的那几次也要算上
            let lower = max(origin, first - span)
            let upper = min(last, until)
            guard lower <= upper else { continue }

            for day in startDays(of: event, origin: origin, in: lower...upper, shiftDays: shiftDays)
            where !exceptions.contains(day) {
                result.append(EventOccurrence(event: event, start: day, end: day + span))
            }
        }
        return result
    }

    /// 某一天的日程，排好序。
    static func occurrences(of events: [CalendarEvent], on key: String, shiftDays: [String: String] = [:]) -> [EventOccurrence] {
        guard let day = DayNumber.of(key) else { return [] }
        return occurrences(of: events, from: day, to: day, shiftDays: shiftDays).sorted(by: EventOccurrence.dayOrder)
    }

    /// 「日期 → 班次 ID」，给跟随班次的日程用。
    static func shiftDays(of document: ScheduleDocument) -> [String: String] {
        guard document.events.contains(where: { $0.recurrence.kind == .shift }) else { return [:] }
        var map: [String: String] = [:]
        for record in document.records where record.planned { map[record.date] = record.shiftId }
        return map
    }

    private static func startDays(of event: CalendarEvent,
                                  origin: Int,
                                  in range: ClosedRange<Int>,
                                  shiftDays: [String: String]) -> [Int] {
        let rule = event.recurrence
        switch rule.kind {
        case .none:
            return range.contains(origin) ? [origin] : []
        case .daily:
            return Array(range)
        case .weekly:
            let days = Set(rule.weekdays.isEmpty ? [DayNumber.weekday(origin)] : rule.weekdays)
            return range.filter { days.contains(DayNumber.weekday($0)) }
        case .monthly:
            let dayOfMonth = DayNumber.civil(origin).day
            return range.filter { DayNumber.civil($0).day == dayOfMonth }
        case .yearly:
            let anchor = DayNumber.civil(origin)
            return range.filter { day in
                let date = DayNumber.civil(day)
                return date.month == anchor.month && date.day == anchor.day
            }
        case .interval:
            let step = max(1, rule.interval)
            return range.filter { ($0 - origin) % step == 0 }
        case .shift:
            guard let shiftId = rule.shiftId else { return [] }
            return range.filter { shiftDays[DayNumber.key($0 - rule.shiftOffset)] == shiftId }
        }
    }

    // MARK: - 周视图排布

    /// 把一周里的日程排成一道一道的色条。
    ///
    /// 长的、先开始的先占道，同一道里不重叠。超过 `lanes` 道的收起来，
    /// 每天收起了几条记在 `hidden` 里，格子上写「+N」。
    /// `visibleColumns` 是这一周里属于当月的那几列，色条不画进上下月的空格子。
    static func layoutWeek(_ occurrences: [EventOccurrence],
                           weekStart: Int,
                           visibleColumns: ClosedRange<Int>,
                           lanes: Int) -> (segments: [EventBarSegment], hidden: [Int: Int]) {
        let firstDay = weekStart + visibleColumns.lowerBound
        let lastDay = weekStart + visibleColumns.upperBound
        let clipped = occurrences
            .filter { $0.end >= firstDay && $0.start <= lastDay }
            .map { occurrence -> (EventOccurrence, Int, Int) in
                (occurrence, max(occurrence.start, firstDay) - weekStart, min(occurrence.end, lastDay) - weekStart)
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                let lhsSpan = lhs.2 - lhs.1, rhsSpan = rhs.2 - rhs.1
                if lhsSpan != rhsSpan { return lhsSpan > rhsSpan }
                return EventOccurrence.dayOrder(lhs.0, rhs.0)
            }

        var laneEnds: [Int] = []
        var segments: [EventBarSegment] = []
        var hidden: [Int: Int] = [:]
        for (occurrence, from, to) in clipped {
            let lane = laneEnds.firstIndex { $0 < from } ?? laneEnds.count
            if lane == laneEnds.count { laneEnds.append(to) } else { laneEnds[lane] = to }
            if lane < lanes {
                segments.append(EventBarSegment(occurrence: occurrence,
                                                column: from,
                                                span: to - from + 1,
                                                lane: lane,
                                                startsHere: occurrence.start == weekStart + from))
            } else {
                for column in from...to { hidden[column, default: 0] += 1 }
            }
        }
        return (segments, hidden)
    }
}
