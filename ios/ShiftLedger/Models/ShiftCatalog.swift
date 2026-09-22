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

/// 班次与标签的可选色板。两组共二十八个色。
///
/// **活力组**（`vividPalette`）是内置班次现在用的一套，明度集中在 0.70–0.78、
/// 彩度顶在色域附近。它当初被排除过，理由是白字压不住（柠黄上只有 1.51:1）——
/// 那个测量没错，错在只想到「把颜色压暗去迁就白字」这一条出路，压完就灰了。
/// 浅色下的简称字统一用白色（见 `Tone.markInk(on:)`），颜色一个像素都不用改。
///
/// **原有十四色**（`classicPalette`）原样留在取色盘上，一个都没少。
///
/// 亮色之间比中等明度的色更难分：活力组前四个的最差 ΔE（普通 / 红绿色盲 / 红色盲取最小）
/// 是 7.6，原有十四色的前四个是 12.9。色标里有简称字做第二编码，所以能接受，
/// 但班次编辑页应该在用户选到太近的两个色时提示一下。
///
/// 内置班次的分配按「白班 = 活力橙、夜班 = 夜班蓝」钉死（这一对分离度 38.5，全表最开），
/// 其余按最大化最小色差贪心排出来。
enum AccentHex {

    // 原有十四色的核心八色
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

    // 活力组：苹果系统色里最亮的那一批，2026-09 补进来。
    //
    // 这一组当初没进色板，理由是白字压不住——systemYellow 上的白字只有 1.51:1。
    // 那个判断本身没错，错在只想到「把颜色压暗去迁就白字」这一条出路，压完就灰了。
    // 试过黑字和同色深字，实际看下来还是白字最清爽，所以现在浅色下统一白字，
    // 颜色一个像素都不用改。
    static let vividOrange = "#FF9500"
    static let vividGreen = "#34C759"
    static let vividCyan = "#32ADE6"
    static let mint = "#00C7BE"
    static let teal = "#30B0C7"
    static let lemon = "#FFCC00"
    static let caramel = "#A2845E"
    /// 夜班蓝。不用 systemBlue #007AFF——它的 OKLCH 明度只有 0.603，
    /// 同色深字压到 4.83 就撞上纯黑的 5.23 封顶了。沿同色相提亮一档到 0.644，
    /// 深字余量回到 6.25，而且离原色只有 ΔE 4.9，肉眼看不出换了色。
    static let navy = "#2E8BFF"

    // 扩展六色：照活力组的调子生成——明度 0.72–0.78、彩度顶到该点色域的 92%，
    // 色相挑离已有色最远的空档。
    static let coral = "#FA8C60"
    static let spring = "#2FC088"
    static let peach = "#F97485"
    static let mustard = "#BCA529"
    static let grass = "#55D82F"
    static let lake = "#2FBCAD"

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

    /// 原来的十四色，顺序不动——已经排上班的人看到的还是同一套。
    static let classicPalette = [pumpkin, indigo, magenta, forest, rose, brick, jade, lavender,
                                 scarlet, purple, royal, sky, olive, amber]
    /// 活力组。内置班次现在全部从这里取色。
    static let vividPalette = [vividOrange, navy, spring, lemon, peach, grass,
                               coral, mint, vividCyan, mustard, vividGreen, teal,
                               lake, caramel]
    /// 取色盘：活力组在前（内置班次用的就是这些），原来的十四色跟在后面，一个都没少。
    static let shiftPalette = vividPalette + classicPalette
    static let tagPalette = [vividGreen, lake, mustard, peach, mint, coral,
                             lavender, jade, magenta, amber, royal, rose]

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
            ShiftDefinition(id: ShiftID.day, name: "白班", shortName: "白", color: AccentHex.vividOrange,
                            startTime: "08:00", endTime: "20:00",
                            defaultHours: hours["day"] ?? 12, legacyType: "day"),
            ShiftDefinition(id: ShiftID.night, name: "夜班", shortName: "夜", color: AccentHex.navy,
                            startTime: "20:00", endTime: "08:00", crossesMidnight: true,
                            defaultHours: hours["night"] ?? 12, legacyType: "night"),
            ShiftDefinition(id: ShiftID.morning, name: "早班", shortName: "早", color: AccentHex.spring,
                            startTime: "08:00", endTime: "16:00",
                            defaultHours: hours["morning"] ?? 8, legacyType: "morning"),
            ShiftDefinition(id: ShiftID.middle, name: "中班", shortName: "中", color: AccentHex.lemon,
                            startTime: "16:00", endTime: "00:00",
                            defaultHours: hours["middle"] ?? 8, legacyType: "middle"),
            ShiftDefinition(id: ShiftID.late, name: "晚班", shortName: "晚", color: AccentHex.peach,
                            startTime: "00:00", endTime: "08:00",
                            defaultHours: hours["late"] ?? 8, legacyType: "late"),
            ShiftDefinition(id: ShiftID.rest, name: "休息", shortName: "休", color: AccentHex.neutral,
                            isRest: true, defaultHours: 0, countsAsWork: false, legacyType: "rest"),
            ShiftDefinition(id: ShiftID.leave, name: "请假", shortName: "假", color: AccentHex.caramel,
                            isRest: true, defaultHours: 0, countsAsWork: false, legacyType: "leave"),
            ShiftDefinition(id: ShiftID.custom, name: "其他", shortName: "工", color: AccentHex.grass,
                            defaultHours: 0, legacyType: "custom"),
            ShiftDefinition(id: ShiftID.duty, name: "责班", shortName: "责", color: AccentHex.coral,
                            startTime: "08:00", endTime: "16:00", defaultHours: 8),
            ShiftDefinition(id: ShiftID.clinic, name: "门诊", shortName: "诊", color: AccentHex.mint,
                            startTime: "08:00", endTime: "16:00", defaultHours: 8),
        ]
    }

    /// 首次启动带的班次。只给最常用的四个，其余在设置页按需添加。
    static func base(hours: [String: Double] = [:]) -> [ShiftDefinition] {
        let order = [ShiftID.day, ShiftID.night, ShiftID.rest, ShiftID.leave]
        let catalog = Dictionary(uniqueKeysWithValues: all(hours: hours).map { ($0.id, $0) })
        return order.compactMap { catalog[$0] }
    }

    /// 医护 / 公共安全预设额外补的班次。
    static func extra(_ id: String) -> ShiftDefinition? {
        switch id {
        case ShiftID.smallNight:
            ShiftDefinition(id: ShiftID.smallNight, name: "小夜", shortName: "小夜", color: AccentHex.vividCyan,
                            startTime: "16:00", endTime: "00:00", defaultHours: 8)
        case ShiftID.bigNight:
            ShiftDefinition(id: ShiftID.bigNight, name: "大夜", shortName: "大夜", color: AccentHex.mustard,
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
        ]
    }

    /// 首次启动预置的模板。
    static let starterTemplateIDs: Set<String> = [
        "tpl-four-two", "tpl-two-rest-two", "tpl-one-one-two",
    ]

    /// 下线的内置模板。三班倒那三套用的人少，列表里只留两班倒的三套；
    /// 老数据里存着的也在读盘时一并清掉（用户自己存的模板 ID 是随机的，不会误删）。
    static let retiredTemplateIDs: Set<String> = [
        "tpl-three-shift", "tpl-double-three", "tpl-four-team-three-shift",
    ]

    /// 首次启动带的职责标签。
    static func baseTags() -> [DutyTag] {
        [
            DutyTag(id: "tag-substitute", name: "代班", shortName: "代", color: AccentHex.vividGreen),
            DutyTag(id: "tag-charge", name: "责班", shortName: "责", color: AccentHex.lake),
            DutyTag(id: "tag-onduty", name: "值班", shortName: "值", color: AccentHex.mustard),
        ]
    }

    static func makeId(_ prefix: String) -> String {
        "\(prefix)-\(UUID().uuidString.prefix(8).lowercased())"
    }
}
