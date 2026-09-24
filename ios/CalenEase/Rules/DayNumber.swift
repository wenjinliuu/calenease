import Foundation

/// 日期键和「天序号」之间的换算：1970-01-01 是第 0 天。
///
/// 日程重复、跨天色条、倒计时都要大量做「隔了几天」「是周几」这类运算。
/// 走 `Calendar` 每次都要建日期对象，翻一个月要算上千次；这里用纯整数的
/// 公历换算（Howard Hinnant 的 days_from_civil），不碰时区，也不分配对象。
enum DayNumber {

    /// "yyyy-MM-dd" → 天序号。格式不对返回 nil。
    static func of(_ key: String) -> Int? {
        let utf8 = Array(key.utf8)
        guard utf8.count == 10, utf8[4] == 45, utf8[7] == 45 else { return nil }
        func number(_ range: Range<Int>) -> Int? {
            var value = 0
            for index in range {
                let digit = Int(utf8[index]) - 48
                guard (0...9).contains(digit) else { return nil }
                value = value * 10 + digit
            }
            return value
        }
        guard let year = number(0..<4), let month = number(5..<7), let day = number(8..<10),
              (1...12).contains(month), (1...31).contains(day)
        else { return nil }
        return from(year: year, month: month, day: day)
    }

    /// 公历年月日（月一基）→ 天序号。
    static func from(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yoe = y - era * 400
        let doy = (153 * (month + (month > 2 ? -3 : 9)) + 2) / 5 + day - 1
        let doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146_097 + doe - 719_468
    }

    /// 天序号 → 公历年月日（月一基）。
    static func civil(_ number: Int) -> (year: Int, month: Int, day: Int) {
        let z = number + 719_468
        let era = (z >= 0 ? z : z - 146_096) / 146_097
        let doe = z - era * 146_097
        let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
        let mp = (5 * doy + 2) / 153
        let day = doy - (153 * mp + 2) / 5 + 1
        let month = mp < 10 ? mp + 3 : mp - 9
        return (yoe + era * 400 + (month <= 2 ? 1 : 0), month, day)
    }

    /// 天序号 → "yyyy-MM-dd"。
    static func key(_ number: Int) -> String {
        let date = civil(number)
        return String(format: "%04d-%02d-%02d", date.year, date.month, date.day)
    }

    /// 周一 = 0 … 周日 = 6，和 `ScheduleCalendar.weekdayIndex` 一致。1970-01-01 是周四。
    static func weekday(_ number: Int) -> Int {
        ((number + 3) % 7 + 7) % 7
    }

    static func isLeapYear(_ year: Int) -> Bool {
        (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    }
}
