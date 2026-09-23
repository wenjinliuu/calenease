import Foundation

/// 国务院公布的放假与调休安排。
///
/// 数据唯一来源是 NateScarlet/holiday-cn，由仓库里的「Update China holidays」工作流
/// 抓取、校验后发布到腾讯云 `holidays/v1/`（见 `docs/holidays-v1.md`）。App 打包时带一份
/// `holidays/v1/` 快照，运行时再从线上更新，见 `HolidayData`。
///
/// 这里只管「这天放假还是调休上班」。源数据里的 `name` 是整段假期的名字——2026 年
/// 2 月 15 日到 23 日每天都写着「春节」——不能拿来当节日名显示，节日名见 `Festivals`。
enum DayAdjustment: String, Codable, Hashable, Sendable {
    /// 放假。
    case off
    /// 调休上班。
    case work
}

/// `holidays/v1/{year}.json`。
struct HolidayYearFile: Codable, Hashable, Sendable {
    struct Day: Codable, Hashable, Sendable {
        let date: String
        let name: String
        let type: DayAdjustment
    }

    let schemaVersion: Int
    let year: Int
    let days: [Day]
}

/// `holidays/v1/index.json`。
struct HolidayIndex: Codable, Sendable {
    struct Entry: Codable, Sendable {
        let url: String
        let sha256: String
        let updatedAt: String
    }

    let schemaVersion: Int
    let years: [String: Entry]
}

struct HolidayCalendar: Hashable, Sendable {
    private(set) var adjustments: [String: DayAdjustment] = [:]
    /// 有安排的年份。
    ///
    /// 只认至少有一天放假的年份文件：下一年还没公布时源仓库会先放一个空文件
    /// （2026 年 9 月时的 2027.json 就是 `"days": []`），把它当成「这一年一天假都没有」
    /// 会把基本工时算多。
    private(set) var coveredYears: Set<Int> = []

    static let empty = HolidayCalendar()

    init() {}

    init<Files: Sequence>(files: Files) where Files.Element == HolidayYearFile {
        for file in files where file.schemaVersion == 1 {
            if file.days.contains(where: { $0.type == .off }) { coveredYears.insert(file.year) }
            // 源文件会带上相邻年份的日子（元旦假期从前一年 12 月 31 日开始之类），
            // 按日期合并即可，发布端已经校验过同一天在不同文件里不会矛盾。
            for day in file.days { adjustments[day.date] = day.type }
        }
    }

    func adjustment(on key: String) -> DayAdjustment? { adjustments[key] }

    func covers(year: Int) -> Bool { coveredYears.contains(year) }

    /// 按国务院安排这一天是不是工作日：调休上班算，放假不算，其余看是不是周末。
    /// 这一年还没有安排时返回 nil，由调用方退回本地推算。
    func isWorkday(_ key: String) -> Bool? {
        guard let year = Int(key.prefix(4)), covers(year: year) else { return nil }
        switch adjustments[key] {
        case .off: return false
        case .work: return true
        case nil: return !ScheduleCalendar.isWeekend(key)
        }
    }

    // MARK: - 当前生效的一份

    private static let lock = NSLock()
    private static var current = HolidayCalendar()

    /// App 当前用的安排。基本工时推算默认读它；由 `ScheduleStore` 在读到快照、
    /// 下载到新数据时替换。单元测试里保持为空，走本地推算，结果不随数据更新漂移。
    static var shared: HolidayCalendar {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
