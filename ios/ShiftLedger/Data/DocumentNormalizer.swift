import Foundation

/// 导入外部 JSON（网页版导出的备份、v1 老数据）时的清洗与迁移。
///
/// 逐条对应 web 版 `normalizeAppData` / `migrateLegacyData`：
/// 认不出来的字段一律回落到默认值，宁可丢一条脏记录也不整份失败。
enum DocumentNormalizer {

    /// 备份文件的最外层可能是 `{ app, version, data }`，也可能直接是数据本体。
    static func document(fromBackup raw: Any) -> ScheduleDocument {
        guard let object = raw as? [String: Any] else { return .makeDefault() }
        if let payload = object["data"] { return document(from: payload) }
        if object["settings"] != nil || object["records"] != nil {
            return migrateLegacy(settings: object["settings"], records: object["records"])
        }
        return document(from: object)
    }

    static func document(from raw: Any) -> ScheduleDocument {
        guard let object = raw as? [String: Any] else { return .makeDefault() }
        guard (object["dataVersion"] as? Int) == ScheduleDocument.version,
              let rawShifts = object["shifts"] as? [Any]
        else {
            return migrateLegacy(settings: object["settings"], records: object["records"])
        }

        let fallback = ScheduleDocument.makeDefault()
        var document = ScheduleDocument()

        let shifts = unique(rawShifts.compactMap(shift(from:)))
        document.shifts = shifts.isEmpty ? fallback.shifts : shifts
        let shiftIds = Set(document.shifts.map(\.id))

        document.tags = unique((object["tags"] as? [Any] ?? []).compactMap(tag(from:)))
        let tagIds = Set(document.tags.map(\.id))

        document.careerPreset = CareerPreset(rawValue: object["careerPreset"] as? String ?? "") ?? .manufacturing

        let templates = unique((object["cycleTemplates"] as? [Any] ?? []).compactMap { template(from: $0, shiftIds: shiftIds) })
            .filter { !ShiftCatalog.retiredTemplateIDs.contains($0.id) }
        document.cycleTemplates = templates.isEmpty
            ? ShiftCatalog.builtInTemplates().filter { $0.shiftIds.allSatisfy(shiftIds.contains) }
            : templates

        document.activeCycle = activeCycle(from: object["activeCycle"], shiftIds: shiftIds)
        document.display = display(from: object["display"] as? [String: Any] ?? [:])
        document.work = work(from: object["work"] as? [String: Any] ?? [:])

        if let rawTargets = object["targets"] as? [String: Any] {
            document.targets = rawTargets.compactMapValues { value in
                guard let number = number(value), number >= 0 else { return nil }
                return number
            }
        }

        document.records = (object["records"] as? [Any] ?? [])
            .compactMap { record(from: $0, shiftIds: shiftIds, tagIds: tagIds) }
            .sorted { $0.date < $1.date }
        return document
    }

    /// v1（`day / night / rest` 那一代）数据的迁移。
    static func migrateLegacy(settings settingsRaw: Any?, records recordsRaw: Any?) -> ScheduleDocument {
        let settings = settingsRaw as? [String: Any] ?? [:]
        var document = ScheduleDocument.makeDefault()

        document.shifts = ShiftCatalog.all(hours: [
            "day": number(settings["dayHours"]) ?? 12,
            "night": number(settings["nightHours"]) ?? 12,
            "morning": number(settings["morningHours"]) ?? 8,
            "middle": number(settings["middleHours"]) ?? 8,
            "late": number(settings["lateHours"]) ?? 8,
        ])
        let shiftIds = Set(document.shifts.map(\.id))
        document.work.dailyStandard = number(settings["dailyStandard"]) ?? 8

        if let rawTargets = settings["targets"] as? [String: Any] {
            document.targets = rawTargets.compactMapValues { value in
                guard let number = number(value), number >= 0 else { return nil }
                return number
            }
        }

        let legacyCycle = (settings["cycle"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .compactMap { ShiftID.legacyMap[$0] }
        if !legacyCycle.isEmpty, let start = settings["cycleStart"] as? String, !start.isEmpty {
            document.activeCycle = ActiveCycle(id: "cycle-migrated", name: "原有循环",
                                               startDate: start, shiftIds: legacyCycle)
        }

        document.records = (recordsRaw as? [Any] ?? [])
            .compactMap { record(from: $0, shiftIds: shiftIds, tagIds: []) }
            .sorted { $0.date < $1.date }
        return document
    }

    // MARK: - 逐字段清洗

    private static func shift(from raw: Any) -> ShiftDefinition? {
        guard let item = raw as? [String: Any],
              let id = item["id"] as? String,
              let name = item["name"] as? String
        else { return nil }
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let shortName = (item["shortName"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let isRest = item["isRest"] as? Bool ?? false
        return ShiftDefinition(
            id: id,
            name: trimmedName.isEmpty ? "未命名班次" : trimmedName,
            shortName: shortName.isEmpty ? String(name.prefix(2)) : String(shortName.prefix(4)),
            color: id == ShiftID.rest
                ? AccentHex.gray
                : AccentHex.normalize(item["color"] as? String ?? AccentHex.shiftPalette[0]),
            startTime: item["startTime"] as? String ?? "",
            endTime: item["endTime"] as? String ?? "",
            crossesMidnight: item["crossesMidnight"] as? Bool ?? false,
            isRest: isRest,
            defaultHours: max(0, number(item["defaultHours"]) ?? 0),
            countsAsWork: (item["countsAsWork"] as? Bool ?? true) && !isRest,
            note: item["note"] as? String,
            legacyType: item["legacyType"] as? String
        )
    }

    private static func tag(from raw: Any) -> DutyTag? {
        guard let item = raw as? [String: Any],
              let id = item["id"] as? String,
              let name = item["name"] as? String
        else { return nil }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        let shortName = (item["shortName"] as? String)?.trimmingCharacters(in: .whitespaces)
        return DutyTag(
            id: id,
            name: trimmed.isEmpty ? "未命名标签" : trimmed,
            shortName: shortName.map { String($0.prefix(6)) } ?? String(name.prefix(3)),
            color: AccentHex.normalize(item["color"] as? String ?? AccentHex.tagPalette[0])
        )
    }

    private static func template(from raw: Any, shiftIds: Set<String>) -> CycleTemplate? {
        guard let item = raw as? [String: Any],
              let id = item["id"] as? String,
              let name = item["name"] as? String
        else { return nil }
        let ids = (item["shiftIds"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .filter(shiftIds.contains)
        guard !ids.isEmpty else { return nil }
        return CycleTemplate(
            id: id,
            name: name,
            caption: item["caption"] as? String ?? "",
            shiftIds: ids,
            category: CycleCategory(rawValue: item["category"] as? String ?? "") ?? .manufacturing,
            builtIn: item["builtIn"] as? Bool ?? false
        )
    }

    private static func activeCycle(from raw: Any?, shiftIds: Set<String>) -> ActiveCycle? {
        guard let item = raw as? [String: Any],
              let startDate = item["startDate"] as? String
        else { return nil }
        let ids = (item["shiftIds"] as? [Any] ?? [])
            .compactMap { $0 as? String }
            .filter(shiftIds.contains)
        guard !ids.isEmpty else { return nil }
        return ActiveCycle(id: item["id"] as? String ?? ShiftCatalog.makeId("cycle"),
                           name: item["name"] as? String ?? "我的循环",
                           startDate: startDate,
                           shiftIds: ids)
    }

    private static func record(from raw: Any, shiftIds: Set<String>, tagIds: Set<String>) -> DayRecord? {
        guard let item = raw as? [String: Any],
              let date = item["date"] as? String
        else { return nil }
        let legacy = (item["shift"] as? String).flatMap { ShiftID.legacyMap[$0] }
        let shiftId = item["shiftId"] as? String ?? legacy ?? ""
        guard shiftIds.contains(shiftId) else { return nil }
        return DayRecord(
            date: date,
            shiftId: shiftId,
            hours: max(0, number(item["hours"]) ?? 0),
            tagIds: (item["tagIds"] as? [Any] ?? []).compactMap { $0 as? String }.filter(tagIds.contains),
            completed: item["completed"] as? Bool ?? false,
            planned: item["planned"] as? Bool ?? true,
            note: item["note"] as? String,
            manualOvertime: number(item["manualOvertime"]).map { max(0, $0) },
            source: RecordSource(rawValue: item["source"] as? String ?? "") ?? .legacy,
            cycleId: item["cycleId"] as? String
        )
    }

    private static func display(from raw: [String: Any]) -> CalendarDisplaySettings {
        CalendarDisplaySettings(
            showShift: raw["showShift"] as? Bool ?? true,
            showTags: raw["showTags"] as? Bool ?? true,
            showShiftTime: raw["showShiftTime"] as? Bool ?? false,
            showHours: raw["showHours"] as? Bool ?? false,
            showHolidays: raw["showHolidays"] as? Bool ?? true,
            showLunar: raw["showLunar"] as? Bool ?? false
        )
    }

    private static func work(from raw: [String: Any]) -> WorkSettings {
        var settings = WorkSettings()
        settings.system = WorkSystem(rawValue: raw["system"] as? String ?? "") ?? .comprehensive
        // web 版把两个开关绑在一起：关掉工时统计，加班统计一并关掉。
        settings.trackHours = raw["trackHours"] as? Bool ?? true
        settings.trackOvertime = settings.trackHours
        if settings.system == .comprehensive {
            settings.period = .month
        } else {
            settings.period = StatisticsPeriod(rawValue: raw["period"] as? String ?? "") ?? .year
        }
        let start = Int(number(raw["annualStartMonth"]) ?? 1)
        settings.annualStartMonth = (1...12).contains(start) ? start : 1
        settings.dailyStandard = max(0, number(raw["dailyStandard"]) ?? 8)
        settings.weeklyStandard = max(0, number(raw["weeklyStandard"]) ?? 40)
        settings.standardDailyEnabled = raw["standardDailyEnabled"] as? Bool ?? true
        settings.standardWeeklyEnabled = raw["standardWeeklyEnabled"] as? Bool ?? true
        let rule = CustomOvertimeRule(rawValue: raw["customRule"] as? String ?? "") ?? .manual
        settings.customRule = rule
        settings.customThreshold = max(0, number(raw["customThreshold"]) ?? 0)
        settings.compensation = CompensationMode(rawValue: raw["compensation"] as? String ?? "") ?? .hours
        return settings
    }

    // MARK: - 小工具

    private static func number(_ raw: Any?) -> Double? {
        switch raw {
        case let value as Double: value.isFinite ? value : nil
        case let value as Int: Double(value)
        case let value as NSNumber: value.doubleValue.isFinite ? value.doubleValue : nil
        case let value as String: Double(value)
        default: nil
        }
    }

    private static func unique<T: Identifiable>(_ items: [T]) -> [T] where T.ID == String {
        var seen = Set<String>()
        return items.filter { item in
            guard !item.id.isEmpty, !seen.contains(item.id) else { return false }
            seen.insert(item.id)
            return true
        }
    }
}
