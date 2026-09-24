import Foundation

/// 一条要排的本机通知。
struct PlannedReminder: Hashable, Sendable {
    let id: String
    let fireDate: Date
    let title: String
    let body: String
}

/// 从数据里算出接下来要提醒的事。纯函数，不碰通知中心，方便测。
///
/// iOS 一个 App 同时最多排 64 条待发通知，所以只看未来 `horizonDays` 天、
/// 只取最早的 `limit` 条；每次回到前台或数据变了再往后补。
enum ReminderPlanner {

    static func plan(_ document: ScheduleDocument,
                     now: Date,
                     horizonDays: Int = 14,
                     limit: Int = 60,
                     calendar: Calendar = ScheduleCalendar.calendar) -> [PlannedReminder] {
        let settings = document.reminders
        let todayKey = key(now, calendar: calendar)
        guard let today = DayNumber.of(todayKey) else { return [] }
        let lastDay = today + horizonDays
        var items: [PlannedReminder] = []

        // 班次：上班前、下班后
        if document.features.shiftsEnabled, settings.shiftStartEnabled || settings.clockOutEnabled {
            let excluded = Set(settings.shiftStartExcluded)
            // 前一天的夜班可能今天才下班，所以从昨天看起
            for record in document.records where record.planned {
                guard let day = DayNumber.of(record.date), day >= today - 1, day <= lastDay,
                      let shift = document.shift(record.shiftId),
                      shift.countsAsWork, !shift.isRest,
                      case let times = record.times(for: shift),
                      let start = minutes(of: times.start), let end = minutes(of: times.end)
                else { continue }
                // 这天单独改过时间的，按改过的时间提醒；结束不晚于开始就是跨天
                let crosses = record.hasCustomTime ? end <= start : (shift.crossesMidnight || end <= start)
                let endDay = crosses ? day + 1 : day

                if settings.shiftStartEnabled, !excluded.contains(shift.id),
                   let fire = date(day: day, minutes: start - settings.shiftStartMinutes, calendar: calendar) {
                    items.append(PlannedReminder(
                        id: "shift-start-\(record.date)",
                        fireDate: fire,
                        title: "\(shift.name)快开始了",
                        body: "\(record.fullRange(for: shift))，\(lead(settings.shiftStartMinutes))后上班。"))
                }
                if settings.clockOutEnabled,
                   let fire = date(day: endDay, minutes: end + settings.clockOutMinutes, calendar: calendar) {
                    items.append(PlannedReminder(
                        id: "clock-out-\(record.date)",
                        fireDate: fire,
                        title: "记得下班打卡",
                        body: "\(shift.name)已在 \(times.end) 结束。"))
                }
            }
        }

        // 日程
        let occurrences = EventEngine.occurrences(of: document.events.filter { $0.reminderMinutes != nil },
                                                  from: today - 1,
                                                  to: lastDay + 1,
                                                  shiftDays: EventEngine.shiftDays(of: document))
        for occurrence in occurrences {
            guard let lead = occurrence.event.reminderMinutes else { continue }
            let event = occurrence.event
            let fire: Date?
            if event.isAllDay {
                let at = minutes(of: settings.allDayEventTime) ?? 9 * 60
                fire = date(day: occurrence.start - (lead >= 1440 ? 1 : 0), minutes: at, calendar: calendar)
            } else if let start = minutes(of: event.startTime) {
                fire = date(day: occurrence.start, minutes: start - lead, calendar: calendar)
            } else {
                fire = nil
            }
            guard let fire else { continue }
            let when = event.isAllDay ? (lead >= 1440 ? "明天" : "今天") : "\(event.startTime) 开始"
            items.append(PlannedReminder(id: "event-\(occurrence.id)",
                                         fireDate: fire,
                                         title: event.title,
                                         body: event.isAllDay ? "\(when)全天" : when))
        }

        // 倒数日当天
        if settings.countdownEnabled {
            let at = minutes(of: settings.countdownTime) ?? 9 * 60
            for countdown in document.countdowns where countdown.kind == .countdown && countdown.remind {
                guard let status = CountdownMath.status(of: countdown, today: todayKey),
                      let target = DayNumber.of(status.targetDate), target >= today, target <= lastDay,
                      let fire = date(day: target, minutes: at, calendar: calendar)
                else { continue }
                items.append(PlannedReminder(id: "countdown-\(countdown.id)-\(status.targetDate)",
                                             fireDate: fire,
                                             title: countdown.title,
                                             body: "就是今天。"))
            }
        }

        return Array(items.filter { $0.fireDate > now }.sorted { $0.fireDate < $1.fireDate }.prefix(limit))
    }

    // MARK: - 小工具

    static func minutes(of clock: String) -> Int? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute)
        else { return nil }
        return hour * 60 + minute
    }

    /// 某天零点加若干分钟（可以是负数，落到前一天）。
    static func date(day: Int, minutes: Int, calendar: Calendar) -> Date? {
        let date = DayNumber.civil(day)
        guard let midnight = calendar.date(from: DateComponents(year: date.year, month: date.month, day: date.day))
        else { return nil }
        return calendar.date(byAdding: .minute, value: minutes, to: midnight)
    }

    private static func key(_ date: Date, calendar: Calendar) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 1970, parts.month ?? 1, parts.day ?? 1)
    }

    /// 「1 小时」「30 分钟」「1 小时 30 分钟」。
    static func lead(_ minutes: Int) -> String {
        let hours = minutes / 60, rest = minutes % 60
        if hours > 0 && rest > 0 { return "\(hours) 小时 \(rest) 分钟" }
        if hours > 0 { return "\(hours) 小时" }
        return "\(rest) 分钟"
    }
}
