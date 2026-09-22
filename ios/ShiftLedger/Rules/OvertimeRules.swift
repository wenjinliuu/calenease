import Foundation

/// 加班判定。逐条移植自 web 版 `calculateOvertime`，
/// `Tests/ShiftLedgerTests/OvertimeRulesTests.swift` 就是照着
/// web 版 `tests/schedule.test.ts` 写的，两端结论必须一致。
enum OvertimeRules {

    /// - Parameter standardTarget: 综合计算工时下这段周期的基本工时。
    static func overtime(records: [DayRecord],
                         settings: WorkSettings,
                         standardTarget: Double) -> Double {
        guard settings.trackHours, settings.trackOvertime else { return 0 }
        let total = records.reduce(0) { $0 + max(0, $1.hours) }

        // 综合计算工时：整段周期的总工时减基本工时，允许为负。
        // 上不满基本工时时这里就是欠的那部分，和「基本工时」那张卡对得上：
        // 计划工时 − 基本工时 = 额外工时。
        if settings.system == .comprehensive {
            return total - standardTarget
        }

        if settings.system == .manual || settings.system == .irregular
            || (settings.system == .custom && settings.customRule == .manual) {
            return records.reduce(0) { $0 + max(0, $1.manualOvertime ?? 0) }
        }

        if settings.system == .custom {
            switch settings.customRule {
            case .daily:
                return records.reduce(0) { $0 + max(0, $1.hours - settings.customThreshold) }
            case .weekly:
                return weeklyTotals(records).reduce(0) { $0 + max(0, $1 - settings.customThreshold) }
            default:
                // 和综合计算工时同一个形状：整段周期的总量减阈值，同样允许为负。
                return total - settings.customThreshold
            }
        }

        // 标准工时是逐日 / 逐周各自超出的累加，少上的那天并不抵消多上的那天，
        // 所以这一支不取负——它算的是「加了多少班」，不是「和基本工时差多少」。
        // 标准工时：日、周两个口径各算一遍，取大的那个。
        let daily = settings.standardDailyEnabled
            ? records.reduce(0) { $0 + max(0, $1.hours - settings.dailyStandard) }
            : 0
        let weekly = settings.standardWeeklyEnabled
            ? weeklyTotals(records).reduce(0) { $0 + max(0, $1 - settings.weeklyStandard) }
            : 0
        return max(daily, weekly)
    }

    private static func weeklyTotals(_ records: [DayRecord]) -> [Double] {
        var weeks: [String: Double] = [:]
        for record in records {
            let key = ScheduleCalendar.startOfWeek(record.date)
            weeks[key, default: 0] += record.hours
        }
        return Array(weeks.values)
    }
}
