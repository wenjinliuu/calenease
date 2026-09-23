import XCTest
@testable import ShiftLedger

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
}
