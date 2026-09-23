import Foundation

/// 本地推算的法定节假日。口径与 web 版 `app/lib/holidays.ts` 一致：
/// 只认《全国年节及纪念日放假办法》规定的法定日，不含调休和补班。
///
/// iOS 端现在的主数据是国务院公布的放假安排（`HolidayCalendar`），节日名走系统农历
/// （`Festivals`）。这里只剩两个用处：
/// - 某一年还没有公布安排、也没下载到数据时，基本工时退回这套本地推算；
/// - 清明是节气，系统农历没有节气接口，`Festivals` 从这里查清明的日子。
enum Holidays {

    /// 查过的日期记下来。日历每翻一页就要把三十来天各判一遍，
    /// 判一次要推好几次日期，同一天没必要算第二遍。
    private static let cacheLock = NSLock()
    private static var nameCache: [String: String] = [:]

    /// 返回法定节假日名称，普通日子返回空串。
    static func name(of key: String) -> String {
        if let cached = cacheLock.withLock({ nameCache[key] }) { return cached }
        let name = computeName(of: key)
        cacheLock.withLock { nameCache[key] = name }
        return name
    }

    private static func computeName(of key: String) -> String {
        guard let parts = ScheduleCalendar.components(from: key) else { return "" }
        let month = parts.month + 1
        let day = parts.day

        if month == 1 && day == 1 { return "元旦" }
        if month == 5 && (day == 1 || day == 2) { return "劳动节" }
        if month == 10 && (1...3).contains(day) { return "国庆节" }
        if month == 4, day == qingmingDay(year: parts.year) { return "清明节" }

        if let spring = lunarNewYear(year: parts.year) {
            // 春节当天与初二、初三
            for offset in 0...2 where ScheduleCalendar.adding(days: offset, to: spring) == key {
                return "春节"
            }
            // 除夕是春节前一天
            if ScheduleCalendar.adding(days: -1, to: spring) == key { return "除夕" }
        }
        if dragonBoat(year: parts.year) == key { return "端午节" }
        if midAutumn(year: parts.year) == key { return "中秋节" }
        return ""
    }

    /// 这一天是不是清明。
    static func isQingming(_ key: String) -> Bool {
        guard let parts = ScheduleCalendar.components(from: key) else { return false }
        return parts.month == 3 && parts.day == qingmingDay(year: parts.year)
    }

    /// 日历格子上的短名，例如"劳动节"显示成"劳动"。
    static func shortName(_ name: String) -> String {
        switch name {
        case "劳动节": "劳动"
        case "国庆节": "国庆"
        case "清明节": "清明"
        case "端午节": "端午"
        case "中秋节": "中秋"
        default: name
        }
    }

    static func isHoliday(_ key: String) -> Bool { !name(of: key).isEmpty }

    // MARK: - 农历日期表

    private static let tableStartYear = 2000
    private static let tableEndYear = 2100

    /// 每年三个节日的公历 "MMdd"，依次是春节、端午、中秋。
    private static let lunarFestivals = "020506060912012406251001021206150921020106040911012206220928020906110918012905311006021806190925020706080914012605281003021406160922020306060912012306230930021006120919013106020908021906200927020806090915012805301004021606180924020506070913012506251001021206140921020106030910012206220929021006100917012905311006021706190925020606090915012605281003021306160922020306050912012306241001021106120919013106010908021906200927020806100916012805301004021506180924020406070913012405271002021206140920020106030910012206220928021006110917013005311005021706190925020606080915012605291004021406150922020206040911012306230930021106130919020106010907021906200926020806100916012805301005021506170924020406060913012406251002021206140921020206030909012106220928020906110917012906011006021706190925020506080915012605281003021406160923020306040911012306230929021106130919013106020908021906200926020706100916012705301005021506170924020506060912012406241001021206140920020206040910012206220928020906110917012906011006021706190926020606070914012605271003021406150922020306050911012406230929021006130918013006020908021806210927020706090916012705291005021506170924020506060913012506240930021206140920020106040909012106230929020906120918"

    /// 1990–2100 年清明的日期，只可能是 4 月 4 日或 5 日。
    private static let qingmingDays = "554555455545554555445544554455445544554455445544554445444544454445444544454445444544444444444444444444444444445"
    private static let qingmingStartYear = 1990

    private static func qingmingDay(year: Int) -> Int {
        let index = year - qingmingStartYear
        guard index >= 0, index < qingmingDays.count else { return fallbackQingming(year: year) }
        let character = qingmingDays[qingmingDays.index(qingmingDays.startIndex, offsetBy: index)]
        return character.wholeNumberValue ?? 5
    }

    /// 超出表格范围时的近似算法（寿星公式，1900–2100 内与实际相符）。
    private static func fallbackQingming(year: Int) -> Int {
        let century = Double(year % 100)
        let value = century * 0.2422 + 4.81 - Double((year % 100) / 4)
        return Int(value)
    }

    private static func festival(year: Int, slot: Int) -> String? {
        let index = year - tableStartYear
        guard index >= 0, index <= tableEndYear - tableStartYear else { return nil }
        let offset = index * 12 + slot * 4
        let start = lunarFestivals.index(lunarFestivals.startIndex, offsetBy: offset)
        let end = lunarFestivals.index(start, offsetBy: 4)
        let piece = lunarFestivals[start..<end]
        guard let month = Int(piece.prefix(2)), let day = Int(piece.suffix(2)) else { return nil }
        return ScheduleCalendar.key(year: year, month: month - 1, day: day)
    }

    /// 正月初一。
    static func lunarNewYear(year: Int) -> String? {
        festival(year: year, slot: 0) ?? systemLunarDate(year: year, lunarMonth: 1, lunarDay: 1)
    }

    /// 五月初五。
    static func dragonBoat(year: Int) -> String? {
        festival(year: year, slot: 1) ?? systemLunarDate(year: year, lunarMonth: 5, lunarDay: 5)
    }

    /// 八月十五。
    static func midAutumn(year: Int) -> String? {
        festival(year: year, slot: 2) ?? systemLunarDate(year: year, lunarMonth: 8, lunarDay: 15)
    }

    /// 表格覆盖不到的年份，用系统农历逐日找。
    private static func systemLunarDate(year: Int, lunarMonth: Int, lunarDay: Int) -> String? {
        var chinese = Calendar(identifier: .chinese)
        chinese.timeZone = .current
        var cursor = ScheduleCalendar.key(year: year, month: 0, day: 1)
        let limit = ScheduleCalendar.key(year: year, month: 11, day: 31)
        while cursor <= limit {
            if let date = ScheduleCalendar.date(from: cursor) {
                let parts = chinese.dateComponents([.month, .day], from: date)
                let isLeap = chinese.dateComponents([.month, .day, .isLeapMonth], from: date).isLeapMonth ?? false
                if !isLeap, parts.month == lunarMonth, parts.day == lunarDay { return cursor }
            }
            cursor = ScheduleCalendar.adding(days: 1, to: cursor)
        }
        return nil
    }
}
