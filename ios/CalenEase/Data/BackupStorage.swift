import Foundation

/// 一份备份文件。iCloud 和本机的放在同一个列表里。
struct BackupItem: Identifiable, Hashable, Sendable {
    enum Location: String, Sendable {
        case iCloud, local

        var label: String { self == .iCloud ? "iCloud" : "本机" }
        var symbol: String { self == .iCloud ? "icloud" : "iphone" }
    }

    enum Kind: Sendable {
        /// 自动备份：同一天（或同一周）反复覆盖同一份。
        case auto
        /// 手动点「立即备份」：永不自动删除。
        case manual
        /// 恢复前自动留的一份当前状态，后悔时能退回去。
        case safety

        var label: String {
            switch self {
            case .auto: "自动"
            case .manual: "手动"
            case .safety: "恢复前快照"
            }
        }
    }

    let name: String
    let location: Location
    let kind: Kind
    let modifiedAt: Date
    let size: Int

    var id: String { location.rawValue + "/" + name }
}

/// 文件名约定。自动备份按周期命名，同一个周期里写的是同一个文件名，于是反复覆盖。
enum BackupNaming {
    static let autoPrefix = "calenease-auto-"
    static let manualPrefix = "calenease-manual-"
    static let safetyPrefix = "calenease-safety-"
    /// 改名「省心日历」之前（循环班表）写的备份文件名前缀。只认不写：
    /// 从旧版拷过来、或旧容器里留下的备份照样列出来、能恢复。
    static let legacyAutoPrefix = "shift-ledger-auto-"
    static let legacyManualPrefix = "shift-ledger-manual-"
    static let legacySafetyPrefix = "shift-ledger-safety-"
    static let suffix = ".json"

    private static func stamp(_ date: Date, format: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    /// 自动备份的文件名：每天一份就写日期，每周一份就写这一周的周一。
    static func autoName(frequency: BackupFrequency, now: Date = Date()) -> String {
        switch frequency {
        case .daily:
            return autoPrefix + stamp(now, format: "yyyyMMdd") + suffix
        case .weekly:
            let monday = ScheduleCalendar.date(from: ScheduleCalendar.startOfWeek(ScheduleCalendar.key(now))) ?? now
            return autoPrefix + stamp(monday, format: "yyyyMMdd") + "-week" + suffix
        }
    }

    static func manualName(now: Date = Date()) -> String {
        manualPrefix + stamp(now, format: "yyyyMMdd-HHmmss") + suffix
    }

    static func safetyName(now: Date = Date()) -> String {
        safetyPrefix + stamp(now, format: "yyyyMMdd-HHmmss") + suffix
    }

    static func kind(of name: String) -> BackupItem.Kind? {
        guard name.hasSuffix(suffix) else { return nil }
        if name.hasPrefix(autoPrefix) || name.hasPrefix(legacyAutoPrefix) { return .auto }
        if name.hasPrefix(manualPrefix) || name.hasPrefix(legacyManualPrefix) { return .manual }
        if name.hasPrefix(safetyPrefix) || name.hasPrefix(legacySafetyPrefix) { return .safety }
        return nil
    }
}

enum BackupFrequency: String, CaseIterable, Identifiable, Sendable {
    case daily, weekly

    var id: String { rawValue }
    var label: String { self == .daily ? "每天一份" : "每周一份" }
}

/// 一个能放备份的地方。所有方法都可能阻塞（iCloud 尤其），只在后台线程调用。
protocol BackupStore: Sendable {
    var location: BackupItem.Location { get }
    /// 现在用不了的原因，nil 表示可用。
    func unavailableReason() -> String?
    func list() throws -> [BackupItem]
    func write(_ data: Data, named name: String) throws
    func read(named name: String) throws -> Data
    func delete(named name: String) throws
    func fileURL(named name: String) throws -> URL
}

extension BackupStore {
    fileprivate func items(in directory: URL) throws -> [BackupItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey]
        let urls = try FileManager.default.contentsOfDirectory(at: directory,
                                                               includingPropertiesForKeys: keys,
                                                               options: [.skipsHiddenFiles])
        return urls.compactMap { url in
            // iCloud 里没下载到本机的文件叫 `.xxx.json.icloud`，去掉外壳认回原名。
            var name = url.lastPathComponent
            if name.hasPrefix("."), name.hasSuffix(".icloud") {
                name = String(name.dropFirst().dropLast(".icloud".count))
            }
            guard let kind = BackupNaming.kind(of: name) else { return nil }
            let values = try? url.resourceValues(forKeys: Set(keys))
            return BackupItem(name: name,
                              location: location,
                              kind: kind,
                              modifiedAt: values?.contentModificationDate ?? .distantPast,
                              size: values?.fileSize ?? 0)
        }
    }
}

// MARK: - 本机

/// 本机备份：App 沙盒 `Documents/Backups`。放在 `Documents` 下，配合 Info.plist 的
/// `UIFileSharingEnabled`，用户在「文件」App 里看得见、拷得走。
/// iCloud 用不了的时候它是唯一还能落地的地方，自动备份不会因此静默失效。
struct LocalBackupStore: BackupStore {
    let location = BackupItem.Location.local

    private func directory() throws -> URL {
        let documents = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask,
                                                    appropriateFor: nil, create: true)
        let folder = documents.appending(path: "Backups", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    func unavailableReason() -> String? { nil }

    func list() throws -> [BackupItem] { try items(in: directory()) }

    func write(_ data: Data, named name: String) throws {
        try data.write(to: directory().appending(path: name), options: .atomic)
    }

    func read(named name: String) throws -> Data {
        try Data(contentsOf: directory().appending(path: name))
    }

    func delete(named name: String) throws {
        try FileManager.default.removeItem(at: directory().appending(path: name))
    }

    func fileURL(named name: String) throws -> URL { try directory().appending(path: name) }
}

// MARK: - iCloud

/// iCloud 备份：把和「导出备份」同格式的 JSON 放进 iCloud 云盘容器的 `Documents`。
///
/// 不是数据同步，是一份份不可变的快照；用户在「文件」App 的 iCloud 云盘里
/// 能看到一个「省心日历」文件夹。容器标识符在 `CalenEase.entitlements` 里声明，两处必须一致。
///
/// 这一套照搬「对个号」踩过的坑：容器首次访问要等几秒、没下载到本机的文件要先拉下来、
/// 写入要走 `NSFileCoordinator`、三种「用不了」要分开说清楚。
struct ICloudBackupStore: BackupStore {
    static let containerID = "iCloud.com.wenjinliu.calenease"

    let location = BackupItem.Location.iCloud

    /// 包里的描述文件声明了哪些 iCloud 容器。读 `embedded.mobileprovision`，
    /// 用来分辨「包本身没带 iCloud 权限」这种用户解决不了的情况。
    static func declaredContainers() -> [String]? {
        guard let url = Bundle.main.url(forResource: "embedded", withExtension: "mobileprovision"),
              let data = try? Data(contentsOf: url),
              let start = data.range(of: Data("<?xml".utf8)),
              let end = data.range(of: Data("</plist>".utf8), options: .backwards),
              let plist = try? PropertyListSerialization.propertyList(
                  from: data[start.lowerBound..<end.upperBound], format: nil) as? [String: Any],
              let entitlements = plist["Entitlements"] as? [String: Any]
        else { return nil }
        let key = "com.apple.developer.ubiquity-container-identifiers"
        if let list = entitlements[key] as? [String] { return list }
        if let single = entitlements[key] as? String { return [single] }
        return []
    }

    /// 容器 URL。App 装好后第一次问时系统往往还在建容器，会先返回 nil，这里最多等 3 秒。
    private func containerURL() -> URL? {
        for attempt in 0..<6 {
            if let url = FileManager.default.url(forUbiquityContainerIdentifier: Self.containerID) {
                return url
            }
            guard FileManager.default.ubiquityIdentityToken != nil else { return nil }
            if attempt < 5 { Thread.sleep(forTimeInterval: 0.5) }
        }
        return nil
    }

    func unavailableReason() -> String? {
        // 只有确实读到了描述文件、里面却没有这个容器，才敢说是打包问题。
        // 模拟器上读不到描述文件，不下结论，照常往下试。
        if let declared = Self.declaredContainers(), !declared.contains(Self.containerID) {
            return "这个版本的安装包没有带上 iCloud 权限，属于打包问题，请反馈给开发者。备份会先存在本机。"
        }
        guard FileManager.default.ubiquityIdentityToken != nil else {
            return "这台设备没有登录 iCloud。登录 Apple 账户后才能备份到 iCloud，现在会先存在本机。"
        }
        guard containerURL() != nil else {
            return "拿不到 iCloud 云盘。请到「设置 → Apple 账户 → iCloud → iCloud 云盘」确认已打开，并允许「省心日历」使用。"
        }
        return nil
    }

    private func directory() throws -> URL {
        guard let container = containerURL() else { throw BackupStoreError.iCloudUnavailable }
        let documents = container.appending(path: "Documents", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        return documents
    }

    func list() throws -> [BackupItem] { try items(in: directory()) }

    func write(_ data: Data, named name: String) throws {
        let url = try directory().appending(path: name)
        try coordinate(writingAt: url, options: .forReplacing) { target in
            try data.write(to: target, options: .atomic)
        }
    }

    func read(named name: String) throws -> Data {
        let url = try directory().appending(path: name)
        if !FileManager.default.fileExists(atPath: url.path) {
            // 换新手机后文件还在云上，先让系统拉下来，最多等 10 秒。
            try? FileManager.default.startDownloadingUbiquitousItem(at: url)
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: url.path), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.3)
            }
        }
        var result: Data?
        var coordinatorError: NSError?
        var readError: Error?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { target in
            do { result = try Data(contentsOf: target) } catch { readError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let readError { throw readError }
        guard let result else { throw BackupStoreError.notDownloaded }
        return result
    }

    func delete(named name: String) throws {
        let url = try directory().appending(path: name)
        try coordinate(writingAt: url, options: .forDeleting) { target in
            try FileManager.default.removeItem(at: target)
        }
    }

    func fileURL(named name: String) throws -> URL { try directory().appending(path: name) }

    private func coordinate(writingAt url: URL,
                            options: NSFileCoordinator.WritingOptions,
                            _ body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var bodyError: Error?
        NSFileCoordinator().coordinate(writingItemAt: url, options: options, error: &coordinatorError) { target in
            do { try body(target) } catch { bodyError = error }
        }
        if let coordinatorError { throw coordinatorError }
        if let bodyError { throw bodyError }
    }
}

enum BackupStoreError: LocalizedError {
    case iCloudUnavailable
    case notDownloaded
    case nowhereToWrite

    var errorDescription: String? {
        switch self {
        case .iCloudUnavailable: "现在用不了 iCloud 云盘。"
        case .notDownloaded: "这份备份还没从 iCloud 下载到本机，请稍后再试。"
        case .nowhereToWrite: "iCloud 和本机都写不进去，这次没有备份成功。"
        }
    }
}
