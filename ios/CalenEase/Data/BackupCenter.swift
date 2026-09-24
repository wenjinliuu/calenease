import CryptoKit
import Foundation
import Observation

/// 备份中心：自动备份、立即备份、备份文件的列表 / 恢复 / 删除。
///
/// 留存规则：
/// - **自动备份按周期覆盖。** 每天（或每周）一个文件名，同一周期里每次退到后台都覆盖这一份，
///   不会越堆越多；跨了周期就换新文件，最多留 `autoKeep` 份，旧的自动回收。
/// - **空数据永远不写自动备份。** 万一数据被清空再退到后台，不能拿空文件把有用的备份挤掉。
/// - **数据没变不重写。** 用内容指纹判断，省得反复写同样的东西。
/// - **手动备份永不自动删除。**
/// - **恢复前先存一份当前状态**（恢复前快照，留最近 `safetyKeep` 份），恢复错了还能退回去。
@MainActor
@Observable
final class BackupCenter {

    nonisolated static let autoKeep = 7
    nonisolated static let safetyKeep = 3

    let cloud: any BackupStore = ICloudBackupStore()
    let local: any BackupStore = LocalBackupStore()

    private(set) var items: [BackupItem] = []
    private(set) var isLoading = false
    /// iCloud 现在为什么用不了，nil 表示可用。
    private(set) var cloudIssue: String?

    // MARK: - 设置（UserDefaults）

    @ObservationIgnored private let defaults = UserDefaults.standard
    private enum Keys {
        static let autoEnabled = "backup.auto.enabled"
        static let useICloud = "backup.iCloud.enabled"
        static let frequency = "backup.auto.frequency"
        static let lastAutoAt = "backup.auto.lastAt"
        static let lastAutoLocation = "backup.auto.lastLocation"
        static let fingerprint = "backup.auto.fingerprint"
    }

    /// 自动备份开关，默认开。
    var autoEnabled: Bool {
        didSet { defaults.set(autoEnabled, forKey: Keys.autoEnabled) }
    }
    /// 备份放 iCloud 还是本机，默认 iCloud。iCloud 用不了时照样落到本机。
    var useICloud: Bool {
        didSet { defaults.set(useICloud, forKey: Keys.useICloud) }
    }
    var frequency: BackupFrequency {
        didSet { defaults.set(frequency.rawValue, forKey: Keys.frequency) }
    }
    private(set) var lastAutoAt: Date?
    private(set) var lastAutoLocation: BackupItem.Location?

    init() {
        autoEnabled = defaults.object(forKey: Keys.autoEnabled) as? Bool ?? true
        useICloud = defaults.object(forKey: Keys.useICloud) as? Bool ?? true
        frequency = BackupFrequency(rawValue: defaults.string(forKey: Keys.frequency) ?? "") ?? .daily
        let stamp = defaults.double(forKey: Keys.lastAutoAt)
        lastAutoAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
        lastAutoLocation = BackupItem.Location(rawValue: defaults.string(forKey: Keys.lastAutoLocation) ?? "")
    }

    private var preferred: BackupItem.Location { useICloud ? .iCloud : .local }

    // MARK: - 列表

    func reload() async {
        isLoading = true
        defer { isLoading = false }
        let cloudStore = cloud, localStore = local
        let result = await Task.detached { () -> ([BackupItem], String?) in
            let issue = cloudStore.unavailableReason()
            var all: [BackupItem] = []
            if issue == nil { all += (try? cloudStore.list()) ?? [] }
            all += (try? localStore.list()) ?? []
            return (all.sorted { $0.modifiedAt > $1.modifiedAt }, issue)
        }.value
        items = result.0
        cloudIssue = result.1
    }

    private func store(for location: BackupItem.Location) -> any BackupStore {
        location == .iCloud ? cloud : local
    }

    // MARK: - 写

    /// 写一份备份。优先放用户选的地方，那里用不了就换另一处，不会什么都不做。
    @discardableResult
    private func write(_ data: Data, named name: String) async throws -> BackupItem.Location {
        let order: [any BackupStore] = preferred == .iCloud ? [cloud, local] : [local, cloud]
        let location = try await Task.detached { () -> BackupItem.Location in
            var lastError: Error?
            for candidate in order where candidate.unavailableReason() == nil {
                do {
                    try candidate.write(data, named: name)
                    return candidate.location
                } catch {
                    lastError = error
                }
            }
            throw lastError ?? BackupStoreError.nowhereToWrite
        }.value
        await prune()
        await reload()
        return location
    }

    /// 立即备份，手动的那种，永不自动删除。
    func backupNow(_ document: ScheduleDocument) async throws -> BackupItem.Location {
        try await write(BackupService.encode(document), named: BackupNaming.manualName())
    }

    /// 自动备份：退到后台时调用。开关关着、数据是空的、数据没变过，都不写。
    func autoBackupIfNeeded(_ document: ScheduleDocument) async {
        guard autoEnabled, !document.records.isEmpty,
              let data = try? BackupService.encode(document)
        else { return }
        // 指纹不含导出时间，只看数据本身。
        let fingerprint = Self.fingerprint(of: document)
        let name = BackupNaming.autoName(frequency: frequency)
        let key = fingerprint + "|" + name
        guard defaults.string(forKey: Keys.fingerprint) != key else { return }
        guard let location = try? await write(data, named: name) else { return }
        defaults.set(key, forKey: Keys.fingerprint)
        lastAutoAt = Date()
        lastAutoLocation = location
        defaults.set(lastAutoAt?.timeIntervalSince1970 ?? 0, forKey: Keys.lastAutoAt)
        defaults.set(location.rawValue, forKey: Keys.lastAutoLocation)
    }

    static func fingerprint(of document: ScheduleDocument) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = (try? encoder.encode(document)) ?? Data()
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - 读、恢复、删

    func document(in item: BackupItem) async throws -> ScheduleDocument {
        let target = store(for: item.location)
        let name = item.name
        let data = try await Task.detached { try target.read(named: name) }.value
        return try BackupService.decode(data: data)
    }

    /// 恢复前先把当前数据存成一份「恢复前快照」，存不下也不拦着恢复。
    func saveSafetySnapshot(of current: ScheduleDocument) async {
        guard !current.records.isEmpty, let data = try? BackupService.encode(current) else { return }
        _ = try? await write(data, named: BackupNaming.safetyName())
    }

    func delete(_ item: BackupItem) async throws {
        let target = store(for: item.location)
        let name = item.name
        try await Task.detached { try target.delete(named: name) }.value
        await reload()
    }

    /// 分享用的文件地址。iCloud 上还没下载的会先下载。
    func shareableURL(for item: BackupItem) async -> URL? {
        let target = store(for: item.location)
        let name = item.name
        return await Task.detached { () -> URL? in
            guard (try? target.read(named: name)) != nil else { return nil }
            return try? target.fileURL(named: name)
        }.value
    }

    // MARK: - 回收

    private func prune() async {
        let stores = [cloud, local]
        await Task.detached {
            for store in stores where store.unavailableReason() == nil {
                guard let all = try? store.list() else { continue }
                for item in Self.expired(in: all) { try? store.delete(named: item.name) }
            }
        }.value
    }

    /// 该回收哪些：自动备份和恢复前快照各留最近几份，手动备份一份不动。
    nonisolated static func expired(in items: [BackupItem]) -> [BackupItem] {
        let sorted = items.sorted { $0.modifiedAt > $1.modifiedAt }
        let autos = sorted.filter { $0.kind == .auto }
        let safeties = sorted.filter { $0.kind == .safety }
        return Array(autos.dropFirst(autoKeep)) + Array(safeties.dropFirst(safetyKeep))
    }
}
