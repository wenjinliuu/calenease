import SwiftUI

@main
struct ShiftLedgerApp: App {
    @State private var store = ScheduleStore()
    @State private var preferences = AppPreferences()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(preferences)
                .preferredColorScheme(preferences.colorScheme)
                .tint(Palette.blue)
                .task {
                    store.load()
                    store.refreshHolidaysIfNeeded()
                }
        }
        .onChange(of: scenePhase) { _, phase in
            // 回到前台顺手看一眼放假安排有没有更新（最多半天查一次）。
            guard phase != .active else {
                store.refreshHolidaysIfNeeded()
                return
            }
            // 退到后台先把未落盘的编辑写下去。
            Task { @MainActor in store.flush() }
        }
    }
}

/// 界面偏好。和排班数据分开，落在 UserDefaults。
@MainActor
@Observable
final class AppPreferences {
    var appearance: Appearance {
        didSet { defaults.set(appearance.rawValue, forKey: Keys.appearance) }
    }

    /// 上次导出备份的时间，超过 14 天在设置页提醒。
    var lastBackupAt: Date? {
        didSet { defaults.set(lastBackupAt?.timeIntervalSince1970 ?? 0, forKey: Keys.lastBackup) }
    }

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let appearance = "shiftLedger.appearance"
        static let lastBackup = "shiftLedger.lastBackupAt"
    }

    init() {
        appearance = Appearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        let stamp = defaults.double(forKey: Keys.lastBackup)
        lastBackupAt = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    var colorScheme: ColorScheme? {
        switch appearance {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }

    var daysSinceBackup: Int? {
        guard let lastBackupAt else { return nil }
        return Calendar.current.dateComponents([.day], from: lastBackupAt, to: Date()).day
    }

    var backupNeedsAttention: Bool {
        guard let days = daysSinceBackup else { return true }
        return days >= 14
    }

    enum Appearance: String, CaseIterable, Identifiable {
        case system, light, dark

        var id: String { rawValue }

        var label: String {
            switch self {
            case .system: "跟随系统"
            case .light: "浅色"
            case .dark: "深色"
            }
        }

        var symbol: String {
            switch self {
            case .system: "circle.lefthalf.filled"
            case .light: "sun.max"
            case .dark: "moon"
            }
        }
    }
}
