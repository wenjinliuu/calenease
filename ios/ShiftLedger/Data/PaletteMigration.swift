import Foundation

/// 换色板之后，把老文件里的班次与标签颜色搬到新色板。
///
/// `ScheduleStore.load()` 解得开一份 v2 文档就直接拿来用，不经过
/// `DocumentNormalizer`，所以 `AccentHex.normalize` 从来碰不到已装用户的颜色——
/// 换了色板之后新装的人拿到新色，老用户还留在旧色上。这里补上这一步。
///
/// 每台设备只跑一次，跑过就记在 `UserDefaults` 里，之后用户自己挑的颜色不会再被覆盖。
enum PaletteMigration {

    /// 色板的代数。以后再整套换色时 +1，老设备会再迁一次。
    static let version = 1
    static let defaultsKey = "palette.migration.version"

    /// 内置班次的新默认色，按班次 ID 取。
    ///
    /// 只靠色值映射不够：白班存的是 `#f6c543`，按色相收敛会落到琥珀，
    /// 但它的新默认色是南瓜橙。所以内置班次认 ID，认不出 ID 的才退回色值映射。
    private static let builtInColors: [String: String] = {
        var map = Dictionary(uniqueKeysWithValues: ShiftCatalog.all().map { ($0.id, $0.color) })
        for id in [ShiftID.smallNight, ShiftID.bigNight, ShiftID.standby] {
            if let shift = ShiftCatalog.extra(id) { map[id] = shift.color }
        }
        return map
    }()

    /// 新色板里的全部色值，小写。
    private static let palette: Set<String> = Set(
        (AccentHex.shiftPalette + AccentHex.tagPalette + [AccentHex.neutral]).map { $0.lowercased() })

    static func isNeeded(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: defaultsKey) < version
    }

    static func markDone(defaults: UserDefaults = .standard) {
        defaults.set(version, forKey: defaultsKey)
    }

    /// 迁移一份文档。没有要改的就原样返回。
    static func migrate(_ document: ScheduleDocument) -> ScheduleDocument {
        var next = document
        next.shifts = document.shifts.map { shift in
            var shift = shift
            shift.color = color(for: shift)
            return shift
        }
        next.tags = document.tags.map { tag in
            var tag = tag
            tag.color = isCurrent(tag.color) ? tag.color : AccentHex.normalize(tag.color)
            return tag
        }
        return next
    }

    /// 已经是新色板里的颜色，说明用户在新版里挑过，不动它。
    private static func isCurrent(_ color: String) -> Bool {
        palette.contains(color.trimmingCharacters(in: .whitespaces).lowercased())
    }

    private static func color(for shift: ShiftDefinition) -> String {
        if isCurrent(shift.color) { return shift.color }
        if let builtIn = builtInColors[shift.id] { return builtIn }
        return AccentHex.normalize(shift.color)
    }
}
