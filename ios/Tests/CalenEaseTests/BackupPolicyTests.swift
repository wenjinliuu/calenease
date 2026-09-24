import XCTest
@testable import CalenEase

/// 备份的命名与回收。「不该删的被删了」一旦上线就不可逆，所以单独测。
final class BackupPolicyTests: XCTestCase {

    private func item(_ name: String, daysAgo: Double) -> BackupItem {
        BackupItem(name: name,
                   location: .local,
                   kind: BackupNaming.kind(of: name) ?? .manual,
                   modifiedAt: Date().addingTimeInterval(-daysAgo * 86_400),
                   size: 100)
    }

    func testAutoBackupOverwritesWithinTheSameDay() {
        let morning = Calendar.current.date(bySettingHour: 8, minute: 0, second: 0, of: Date())!
        let evening = Calendar.current.date(bySettingHour: 21, minute: 30, second: 0, of: Date())!
        XCTAssertEqual(BackupNaming.autoName(frequency: .daily, now: morning),
                       BackupNaming.autoName(frequency: .daily, now: evening))
        XCTAssertNotEqual(BackupNaming.manualName(now: morning), BackupNaming.manualName(now: evening))
    }

    func testNamesRoundTripToTheirKind() {
        XCTAssertEqual(BackupNaming.kind(of: BackupNaming.autoName(frequency: .weekly)), .auto)
        XCTAssertEqual(BackupNaming.kind(of: BackupNaming.manualName()), .manual)
        XCTAssertEqual(BackupNaming.kind(of: BackupNaming.safetyName()), .safety)
        XCTAssertNil(BackupNaming.kind(of: "别的文件.json"))
    }

    func testPruningKeepsRecentAutosAndEveryManualBackup() {
        let autos = (0..<10).map { item("shift-ledger-auto-2026090\($0).json", daysAgo: Double($0)) }
        let manuals = (0..<10).map { item("shift-ledger-manual-2026090\($0)-120000.json", daysAgo: Double($0)) }
        let expired = BackupCenter.expired(in: autos + manuals)
        XCTAssertEqual(expired.count, 10 - BackupCenter.autoKeep)
        XCTAssertTrue(expired.allSatisfy { $0.kind == .auto })
        // 回收的是最旧的那几份
        XCTAssertEqual(Set(expired.map(\.name)), Set(autos.suffix(10 - BackupCenter.autoKeep).map(\.name)))
    }

    func testSecondaryShiftSurvivesAJSONRoundTrip() throws {
        let record = DayRecord(date: "2026-09-23", shiftId: ShiftID.day, secondaryShiftId: ShiftID.night, hours: 20)
        let decoded = try JSONDecoder().decode(DayRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.secondaryShiftId, ShiftID.night)
        // 老数据没有这个字段也能读
        let old = #"{"date":"2026-09-23","shiftId":"day","hours":12,"tagIds":[],"completed":false,"planned":true,"source":"manual"}"#
        XCTAssertNil(try JSONDecoder().decode(DayRecord.self, from: Data(old.utf8)).secondaryShiftId)
    }

    // MARK: - 从「循环班表」改名过来

    func testNewBackupsUseTheCalenEaseName() {
        XCTAssertTrue(BackupNaming.manualName().hasPrefix("calenease-manual-"))
        XCTAssertTrue(BackupNaming.autoName(frequency: .daily).hasPrefix("calenease-auto-"))
    }

    func testLegacyBackupNamesAreStillRecognised() {
        XCTAssertEqual(BackupNaming.kind(of: "shift-ledger-auto-20260901.json"), .auto)
        XCTAssertEqual(BackupNaming.kind(of: "shift-ledger-manual-20260901-120000.json"), .manual)
        XCTAssertEqual(BackupNaming.kind(of: "shift-ledger-safety-20260901-120000.json"), .safety)
    }

    func testLegacyDataFileIsMovedToTheNewName() throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = folder.appending(path: ScheduleStore.legacyFileName)
        try Data("{}".utf8).write(to: legacy)

        let target = folder.appending(path: ScheduleStore.fileName)
        XCTAssertEqual(ScheduleStore.migrateLegacyFile(to: target), target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacy.path))

        // 新文件已经在了就不动旧文件
        try Data("{}".utf8).write(to: legacy)
        XCTAssertEqual(ScheduleStore.migrateLegacyFile(to: target), target)
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacy.path))
    }

    func testDayRecordCustomTimesRoundTripAndOldRecordsStillDecode() throws {
        var record = DayRecord(date: "2026-09-23", shiftId: "day", hours: 8)
        record.startTime = "09:00"
        record.endTime = "17:00"
        let decoded = try JSONDecoder().decode(DayRecord.self, from: JSONEncoder().encode(record))
        XCTAssertEqual(decoded.startTime, "09:00")
        XCTAssertEqual(decoded.endTime, "17:00")

        let old = #"{"date":"2026-09-23","shiftId":"day","hours":12,"tagIds":[],"completed":false,"planned":true,"source":"manual"}"#
        let plain = try JSONDecoder().decode(DayRecord.self, from: Data(old.utf8))
        XCTAssertNil(plain.startTime)
        XCTAssertFalse(plain.hasCustomTime)
    }

    func testCustomTimesRecomputeHoursKeepingTheShiftsBreak() {
        // 08:00–20:00 共 12 小时，默认工时 11 小时：班次本身扣 1 小时休息
        let shift = ShiftDefinition(id: "day", name: "白班", shortName: "白", color: AccentHex.yellow,
                                    startTime: "08:00", endTime: "20:00", defaultHours: 11)
        XCTAssertEqual(shift.hours(startTime: "08:00", endTime: "18:00"), 9, accuracy: 0.001)
        // 跨零点
        XCTAssertEqual(shift.hours(startTime: "20:00", endTime: "06:00"), 9, accuracy: 0.001)

        var record = DayRecord(date: "2026-09-23", shiftId: "day", hours: 9)
        XCTAssertEqual(record.fullRange(for: shift), "08:00–20:00")
        record.startTime = "08:00"
        record.endTime = "18:00"
        XCTAssertEqual(record.fullRange(for: shift), "08:00–18:00")
    }
}
