import Foundation

/// 职业预设。只影响起始推荐的班次、标签和循环模板，不限制任何功能：
/// 切换预设只做加法，已经在用的标签不会被删掉。
enum CareerPresets {

    static func apply(_ preset: CareerPreset, to document: ScheduleDocument) -> ScheduleDocument {
        var next = document
        next.careerPreset = preset

        // 1. 班次：并入这个职业推荐的内置班次
        let catalog = Dictionary(uniqueKeysWithValues: ShiftCatalog.all().map { ($0.id, $0) })
        let additions = recommendedShiftIDs(preset).compactMap { catalog[$0] ?? ShiftCatalog.extra($0) }
        next.shifts = unique(document.shifts + additions)

        // 2. 标签：换掉其它职业的预设标签，但用过的保留
        let usedTagIds = Set(document.records.flatMap(\.tagIds))
        let presetPrefixes = CareerPreset.allCases.map { "tag-\($0.rawValue)-" }
        let retained = document.tags.filter { tag in
            let isPresetTag = presetPrefixes.contains { tag.id.hasPrefix($0) }
            return !isPresetTag || tag.id.hasPrefix("tag-\(preset.rawValue)-") || usedTagIds.contains(tag.id)
        }
        next.tags = unique(retained + presetTags(preset))

        // 3. 模板：补上这个职业常见的循环
        let availableShiftIds = Set(next.shifts.map(\.id))
        var templates = document.cycleTemplates
        for template in ShiftCatalog.builtInTemplates()
        where recommendedCategories(preset).contains(template.category)
            && template.shiftIds.allSatisfy(availableShiftIds.contains)
            && !templates.contains(where: { $0.id == template.id }) {
            templates.append(template)
        }
        if preset == .medical, !templates.contains(where: { $0.id == "tpl-medical-start" }) {
            templates.append(CycleTemplate(id: "tpl-medical-start",
                                           name: "白白 · 小夜 · 大夜 · 休休",
                                           caption: "医疗起始模板，可自由修改",
                                           shiftIds: [ShiftID.day, ShiftID.day, ShiftID.smallNight,
                                                      ShiftID.bigNight, ShiftID.rest, ShiftID.rest],
                                           category: .medical, builtIn: true))
        }
        next.cycleTemplates = templates
        return next
    }

    static func recommendedShiftIDs(_ preset: CareerPreset) -> [String] {
        switch preset {
        case .manufacturing: [ShiftID.day, ShiftID.night, ShiftID.rest]
        case .medical: [ShiftID.day, ShiftID.morning, ShiftID.smallNight, ShiftID.bigNight,
                        ShiftID.rest, ShiftID.standby, ShiftID.duty, ShiftID.clinic]
        case .transport: [ShiftID.morning, ShiftID.middle, ShiftID.late, ShiftID.night, ShiftID.rest]
        case .safety: [ShiftID.day, ShiftID.night, ShiftID.standby, ShiftID.rest]
        case .service: [ShiftID.morning, ShiftID.middle, ShiftID.late, ShiftID.rest]
        case .custom: [ShiftID.rest]
        }
    }

    static func presetTags(_ preset: CareerPreset) -> [DutyTag] {
        let names: [String]
        switch preset {
        case .medical: names = ["责班", "主班", "门诊", "ICU"]
        case .manufacturing: names = ["带班", "机台", "培训"]
        case .transport: names = ["值乘", "调度", "站务"]
        case .safety: names = ["值守", "巡检", "备勤"]
        case .service: names = ["前台", "夜审", "领班"]
        case .custom: names = []
        }
        return names.enumerated().map { index, name in
            DutyTag(id: "tag-\(preset.rawValue)-\(index)",
                    name: name,
                    shortName: name,
                    color: AccentHex.tagPalette[index % AccentHex.tagPalette.count])
        }
    }

    private static func recommendedCategories(_ preset: CareerPreset) -> Set<CycleCategory> {
        switch preset {
        case .transport, .service: [.threeShift]
        case .manufacturing, .safety: [.manufacturing]
        default: []
        }
    }

    private static func unique<T: Identifiable>(_ items: [T]) -> [T] where T.ID == String {
        var seen = Set<String>()
        return items.filter { seen.insert($0.id).inserted }
    }
}
