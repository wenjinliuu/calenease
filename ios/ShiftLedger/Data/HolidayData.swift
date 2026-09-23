import CryptoKit
import Foundation

/// 放假安排的读取与更新。
///
/// 三层，后面的盖前面的：
/// 1. 包里带的快照——打包时仓库 `holidays/v1/` 的原样拷贝，第一次打开没网也有数据；
/// 2. 本机缓存——上次从线上下载、校验过的年份文件；
/// 3. 线上——腾讯云 `holidays/v1/`，最多半天查一次，只下载 SHA-256 变了的年份。
///
/// 只下载公开的节假日表，不带任何用户标识，也不上传任何东西。
enum HolidayData {

    static let indexURL = URL(string:
        "https://wenjin-cloudbase-d1empq882391ac1-1311287495.ap-shanghai.app.tcloudbase.com/holidays/v1/index.json")!

    /// 两次联网检查的最短间隔。数据一年只在年底前后变，半天一查足够。
    static let refreshInterval: TimeInterval = 12 * 60 * 60

    /// 每个年份文件和它的 SHA-256。SHA-256 用来和线上索引比，判断要不要重新下载。
    struct Snapshot: Sendable {
        var files: [Int: HolidayYearFile] = [:]
        var hashes: [Int: String] = [:]

        var calendar: HolidayCalendar { HolidayCalendar(files: files.values) }
    }

    // MARK: - 本地

    /// 包里的快照叠上本机缓存。几十 KB 的 JSON，启动时同步读完。
    static func loadLocal(bundle: Bundle = .main) -> Snapshot {
        var snapshot = Snapshot()
        if let index = bundle.url(forResource: "index", withExtension: "json", subdirectory: "holidays/v1") {
            merge(directory: index.deletingLastPathComponent(), into: &snapshot)
        }
        if let cache = cacheDirectory() {
            merge(directory: cache, into: &snapshot)
        }
        return snapshot
    }

    /// 读一个目录里的 `index.json` 和它列出的年份文件。缓存目录的索引只列下载过的年份。
    private static func merge(directory: URL, into snapshot: inout Snapshot) {
        guard let data = try? Data(contentsOf: directory.appending(path: "index.json")),
              let index = try? JSONDecoder().decode(HolidayIndex.self, from: data),
              index.schemaVersion == 1
        else { return }
        for (yearText, entry) in index.years {
            guard let year = Int(yearText),
                  let bytes = try? Data(contentsOf: directory.appending(path: entry.url)),
                  let file = decode(bytes, year: year)
            else { continue }
            snapshot.files[year] = file
            snapshot.hashes[year] = entry.sha256.lowercased()
        }
    }

    private static func decode(_ bytes: Data, year: Int) -> HolidayYearFile? {
        guard let file = try? JSONDecoder().decode(HolidayYearFile.self, from: bytes),
              file.schemaVersion == 1, file.year == year
        else { return nil }
        return file
    }

    private static func cacheDirectory() -> URL? {
        guard let base = try? FileManager.default.url(for: .applicationSupportDirectory,
                                                      in: .userDomainMask,
                                                      appropriateFor: nil,
                                                      create: true)
        else { return nil }
        let directory = base.appending(path: "holidays/v1", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    // MARK: - 线上

    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 30
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpCookieStorage = nil
        return URLSession(configuration: configuration)
    }()

    /// 拉线上索引，下载 SHA-256 和本地不一样的年份，校验通过的写进缓存。
    /// 返回合并后的新快照；什么都没变返回 nil。网络或格式出错直接抛出，本地数据不动。
    static func refresh(from current: Snapshot) async throws -> Snapshot? {
        let (data, response) = try await session.data(from: indexURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        let index = try JSONDecoder().decode(HolidayIndex.self, from: data)
        guard index.schemaVersion == 1 else { return nil }

        var next = current
        var downloaded: [Int: (entry: HolidayIndex.Entry, bytes: Data)] = [:]
        for (yearText, entry) in index.years {
            guard let year = Int(yearText) else { continue }
            let expected = entry.sha256.lowercased()
            guard current.hashes[year] != expected,
                  let url = URL(string: entry.url, relativeTo: indexURL)?.absoluteURL
            else { continue }
            let (bytes, yearResponse) = try await session.data(from: url)
            // 状态码、SHA-256、结构、年份任何一项对不上就跳过这一年，保留本地那份。
            guard (yearResponse as? HTTPURLResponse)?.statusCode == 200,
                  sha256(bytes) == expected,
                  let file = decode(bytes, year: year)
            else { continue }
            next.files[year] = file
            next.hashes[year] = expected
            downloaded[year] = (entry, bytes)
        }
        guard !downloaded.isEmpty else { return nil }
        writeCache(downloaded)
        return next
    }

    /// 缓存目录的索引只记下载过的年份，和包里的快照一起读时按年份覆盖。
    private static func writeCache(_ downloaded: [Int: (entry: HolidayIndex.Entry, bytes: Data)]) {
        guard let directory = cacheDirectory() else { return }
        var years: [String: HolidayIndex.Entry] = [:]
        if let data = try? Data(contentsOf: directory.appending(path: "index.json")),
           let existing = try? JSONDecoder().decode(HolidayIndex.self, from: data) {
            years = existing.years
        }
        for (year, item) in downloaded {
            let name = "\(year).json"
            guard (try? item.bytes.write(to: directory.appending(path: name), options: .atomic)) != nil else { continue }
            years[String(year)] = HolidayIndex.Entry(url: name, sha256: item.entry.sha256, updatedAt: item.entry.updatedAt)
        }
        let index = HolidayIndex(schemaVersion: 1, years: years)
        if let data = try? JSONEncoder().encode(index) {
            try? data.write(to: directory.appending(path: "index.json"), options: .atomic)
        }
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
