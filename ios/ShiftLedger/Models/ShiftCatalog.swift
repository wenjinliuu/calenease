import Foundation

/// 内置班次的固定 ID。与 web 版 `SHIFT_IDS` 一致，备份互导时才能对得上。
enum ShiftID {
    static let day = "shift-day"
    static let night = "shift-night"
    static let morning = "shift-morning"
    static let middle = "shift-middle"
    static let late = "shift-late"
    static let rest = "shift-rest"
    static let leave = "shift-leave"
    static let custom = "shift-custom"
    static let smallNight = "shift-small-night"
    static let bigNight = "shift-big-night"
    static let standby = "shift-standby"
    static let duty = "shift-medical-duty"
    static let clinic = "shift-medical-clinic"

    /// v1 数据里的班次类型到新 ID 的映射。
    static let legacyMap: [String: String] = [
        "day": day, "night": night, "morning": morning, "middle": middle,
        "late": late, "rest": rest, "leave": leave, "custom": custom,
    ]

    /// 设置页与选择器里的固定顺序。
    static let displayOrder = [
        day, night, rest, leave, morning, middle, late,
        smallNight, bigNight, duty, clinic, standby,
    ]
}

/// 班次与标签的可选色板。
///
/// 十四个色，全部高饱和，全部能在 13pt 色标上配白字达到 3:1 以上——
/// 越黄的橙越扛不住白字（systemYellow 上只有 1.51:1，压到达标时已经变成芥末），
/// 所以暖色一律落在朱橙 / 南瓜这一族。
///
/// `shiftPalette` 是按推荐顺序排的：前四个（南瓜 · 靛 · 品红 · 森绿）两两之间在
/// 正常视觉、红绿色盲、红色盲三种情况下的 OKLab ΔE 最差也有 20.4，远高于 15 的门槛；
/// 第五个开始降到 11.5，第八个只剩 5.0。色标里有简称字做第二编码，所以超过四个仍然能用，
/// 但班次编辑页应该在用户选到太近的两个色时提示一下。
enum AccentHex {

    // 核心八色，按推荐顺序
    static let pumpkin = "#F06E15"
    static let indigo = "#5856D6"
    static let magenta = "#C13584"
    static let forest = "#2BA94A"
    static let rose = "#FF2D55"
    static let brick = "#C2410C"
    static let jade = "#00A59E"
    static let lavender = "#8A5CF0"

    // 扩展六色
    static let scarlet = "#FF3B30"
    static let purple = "#AF52DE"
    static let royal = "#1A5FE0"
    static let sky = "#099BE3"
    static let olive = "#7F9B14"
    static let amber = "#CC8300"

    /// 休息、请假、备班这类不计工时的状态。它们是"没有班"，不是"第 N 个班次"，
    /// 所以不占彩色位。
    static let neutral = "#8E8E93"

    // 旧名字保留，指向新色板，老代码不用改
    static let blue = royal
    static let green = forest
    static let yellow = amber
    static let pink = rose
    static let orange = pumpkin
    static let cyan = jade
    static let red = scarlet
    static let gray = neutral

    static let shiftPalette = [pumpkin, indigo, magenta, forest, rose, brick, jade, lavender,
                               scarlet, purple, royal, sky, olive, amber]
    static let tagPalette = [lavender, jade, magenta, amber, royal, forest, rose, sky]

    /// 旧数据里用过的色值，导入时统一收敛到新色板。
    static let legacyMap: [String: String] = [
        // v2 色板
        "#3a83f6": royal, "#53b559": forest, "#f6c543": amber, "#ed77af": rose,
        "#ed7c37": pumpkin, "#a67df2": purple, "#e66770": scarlet, "#55a8c7": sky,
        "#8e8e8e": neutral,
        // v1 色板
        "#2f7df4": royal, "#3377cc": royal, "#5368e8": royal,
        "#665ce8": purple, "#7459d9": purple, "#6a62de": purple,
        "#9b63d9": purple, "#433f9e": indigo,
        "#17a878": jade, "#0d9b82": jade,
        "#ef7d36": pumpkin, "#e89135": amber, "#d66a38": brick,
        "#d65374": rose, "#d14f72": rose,
        "#7a879b": neutral, "#7b8799": neutral, "#8793a5": neutral,
        "#08a2b8": sky,
    ]

    static func normalize(_ color: String) -> String {
        legacyMap[color.trimmingCharacters(in: .whitespaces).lowercased()] ?? color
    }
}

/// 内置班次与内置循环模板。
enum ShiftCatalog {

    /// 全部可选的内置班次。`hours` 用于 v1 数据迁移时带入原来的时长。
    static func all(hours: [String: Double] = [:]) -> [ShiftDefinition] {
        [
            ShiftDefinition(id: ShiftID.day, name: "白班", shortName: "白", color: AccentHex.pumpkin,
                            startTime: "08:00", endTime: "20:00",
                            defaultHours: hours["day"] ?? 12, legacyType: "day"),
            ShiftDefinition(id: ShiftID.night, name: "夜班", shortName: "夜", color: AccentHex.indigo,
                            startTime: "20:00", endTime: "08:00", crossesMidnight: true,
                            defaultHours: hours["night"] ?? 12, legacyType: "night"),
            ShiftDefinition(id: ShiftID.morning, name: "早班", shortName: "早", color: AccentHex.jade,
                            startTime: "08:00", endTime: "16:00",
                            defaultHours: hours["morning"] ?? 8, legacyType: "morning"),
            ShiftDefinition(id: ShiftID.middle, name: "中班", shortName: "中", color: AccentHex.magenta,
                            startTime: "16:00", endTime: "00:00",
                            defaultHours: hours["middle"] ?? 8, legacyType: "middle"),
            ShiftDefinition(id: ShiftID.late, name: "晚班", shortName: "晚", color: AccentHex.lavender,
                            startTime: "00:00", endTime: "08:00",
                            defaultHours: hours["late"] ?? 8, legacyType: "late"),
            ShiftDefinition(id: ShiftID.rest, name: "休息", shortName: "休", color: AccentHex.neutral,
                            isRest: true, defaultHours: 0, countsAsWork: false, legacyType: "rest"),
            ShiftDefinition(id: ShiftID.leave, name: "请假", shortName: "假", color: AccentHex.neutral,
                            isRest: true, defaultHours: 0, countsAsWork: false, legacyType: "leave"),
            ShiftDefinition(id: ShiftID.custom, name: "其他", shortName: "工", color: AccentHex.forest,
                            defaultHours: 0, legacyType: "custom"),
            ShiftDefinition(id: ShiftID.duty, name: "责班", shortName: "责", color: AccentHex.brick,
                            startTime: "08:00", endTime: "16:00", defaultHours: 8),
            ShiftDefinition(id: ShiftID.clinic, name: "门诊", shortName: "诊", color: AccentHex.sky,
                            startTime: "08:00", endTime: "16:00", defaultHours: 8),
        ]
    }

    /// 首次启动带的班次。
    static func base(hours: [String: Double] = [:]) -> [ShiftDefinition] {
        let order = [ShiftID.day, ShiftID.night, ShiftID.rest, ShiftID.leave,
                     ShiftID.morning, ShiftID.middle, ShiftID.late]
        let catalog = Dictionary(uniqueKeysWithValues: all(hours: hours).map { ($0.id, $0) })
        return order.compactMap { catalog[$0] }
    }

    /// 医护 / 公共安全预设额外补的班次。
    static func extra(_ id: String) -> ShiftDefinition? {
        switch id {
        case ShiftID.smallNight:
            ShiftDefinition(id: ShiftID.smallNight, name: "小夜", shortName: "小夜", color: AccentHex.royal,
                            startTime: "16:00", endTime: "00:00", defaultHours: 8)
        case ShiftID.bigNight:
            ShiftDefinition(id: ShiftID.bigNight, name: "大夜", shortName: "大夜", color: AccentHex.purple,
                            startTime: "00:00", endTime: "08:00", defaultHours: 8)
        case ShiftID.standby:
            ShiftDefinition(id: ShiftID.standby, name: "备班", shortName: "备", color: AccentHex.neutral,
                            defaultHours: 0, countsAsWork: false)
        default: nil
        }
    }

    /// 内置循环模板。
    static func builtInTemplates() -> [CycleTemplate] {
        let day = ShiftID.day, night = ShiftID.night, rest = ShiftID.rest
        let morning = ShiftID.morning, middle = ShiftID.middle, late = ShiftID.late
        return [
            CycleTemplate(id: "tpl-four-two", name: "4白2休 · 4夜2休",
                          caption: "白白白白休休 · 夜夜夜夜休休",
                          shiftIds: [day, day, day, day, rest, rest, night, night, night, night, rest, rest],
                          category: .manufacturing, builtIn: true),
            CycleTemplate(id: "tpl-two-rest-two", name: "2白2休 · 2夜2休",
                          caption: "白白休休 · 夜夜休休",
                          shiftIds: [day, day, rest, rest, night, night, rest, rest],
                          category: .manufacturing, builtIn: true),
            CycleTemplate(id: "tpl-one-one-two", name: "1白1夜 · 休2天",
                          caption: "白夜休休",
                          shiftIds: [day, night, rest, rest],
                          category: .manufacturing, builtIn: true),
            CycleTemplate(id: "tpl-two-two-two", name: "2白2夜 · 休2天",
                          caption: "白白夜夜休休",
                          shiftIds: [day, day, night, night, rest, rest],
                          category: .manufacturing, builtIn: true),
            CycleTemplate(id: "tpl-work-two-rest-two", name: "做二休二",
                          caption: "白白休休",
                          shiftIds: [day, day, rest, rest],
                          category: .manufacturing, builtIn: true),
            CycleTemplate(id: "tpl-three-four", name: "3上4休 / 4上3休",
                          caption: "白白白休休休休 · 白白白白休休休",
                          shiftIds: [day, day, day, rest, rest, rest, rest,
                                     day, day, day, day, rest, rest, rest],
                          category: .manufacturing, builtIn: true),
            CycleTemplate(id: "tpl-three-shift", name: "早 → 中 → 夜 → 休",
                          caption: "早中晚休",
                          shiftIds: [morning, middle, late, rest],
                          category: .threeShift, builtIn: true),
            CycleTemplate(id: "tpl-double-three", name: "夜夜 → 中中 → 早早 → 休休",
                          caption: "晚晚中中早早休休",
                          shiftIds: [late, late, middle, middle, morning, morning, rest, rest],
                          category: .threeShift, builtIn: true),
            CycleTemplate(id: "tpl-four-team-three-shift", name: "四班三倒 · 8小时",
                          caption: "早早中中晚晚休休",
                          shiftIds: [morning, morning, middle, middle, late, late, rest, rest],
                          category: .threeShift, builtIn: true),
        ]
    }

    /// 首次启动预置的四个模板。
    static let starterTemplateIDs: Set<String> = [
        "tpl-four-two", "tpl-two-rest-two", "tpl-one-one-two", "tpl-three-shift",
    ]

    static func makeId(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }
}
