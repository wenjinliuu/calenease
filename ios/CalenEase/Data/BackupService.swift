import Foundation
import UniformTypeIdentifiers
import SwiftUI

/// JSON 备份的导出与导入。
///
/// 字段与 web 版导出完全一致（`{ app, version, exportedAt, data }`），
/// 所以 iOS 导出的文件可以直接在网页端导入，反之亦然。
enum BackupService {

    static func encode(_ document: ScheduleDocument) throws -> Data {
        let payload = BackupPayload(app: "calenease",
                                    version: ScheduleDocument.version,
                                    exportedAt: ISO8601DateFormatter().string(from: Date()),
                                    data: document)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// 写到临时目录，交给系统分享面板。
    static func writeTemporaryFile(_ document: ScheduleDocument) throws -> URL {
        let name = "省心日历备份-\(ScheduleCalendar.todayKey).json"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        try encode(document).write(to: url, options: .atomic)
        return url
    }

    /// 读取用户选中的备份文件。认不出结构时按 v1 老数据再试一次。
    static func decode(contentsOf url: URL) throws -> ScheduleDocument {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        let data = try Data(contentsOf: url)
        guard let raw = try? JSONSerialization.jsonObject(with: data) else {
            throw BackupError.unreadable
        }
        let document = DocumentNormalizer.document(fromBackup: raw)
        guard !document.shifts.isEmpty else { throw BackupError.unreadable }
        return document
    }

    /// 从内存里的备份数据还原。备份中心读 iCloud / 本机文件时用。
    static func decode(data: Data) throws -> ScheduleDocument {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else {
            throw BackupError.unreadable
        }
        let document = DocumentNormalizer.document(fromBackup: raw)
        guard !document.shifts.isEmpty else { throw BackupError.unreadable }
        return document
    }

    private struct BackupPayload: Codable {
        let app: String
        let version: Int
        let exportedAt: String
        let data: ScheduleDocument
    }

    enum BackupError: LocalizedError {
        case unreadable

        var errorDescription: String? {
            "读不出这个文件，请选择省心日历（或旧版循环班表）导出的 JSON 备份。"
        }
    }
}
