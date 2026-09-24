import Foundation
import UserNotifications

/// 把 `ReminderPlanner` 算出来的提醒交给系统通知中心。
///
/// 全是本机通知，在设备上排好，不经过任何服务器。每次重排：先撤掉我们自己排过的
/// 那一批（ID 带固定前缀），再按最新数据排一遍。
@MainActor
enum NotificationScheduler {

    static let prefix = "calenease."
    /// 改名前排的通知用这个前缀，重排时一起撤掉，免得旧通知和新通知重复响。
    static let legacyPrefix = "shiftledger."
    private static var pending: Task<Void, Never>?

    /// 数据里有没有任何需要提醒的东西。没有就不去打扰系统、也不弹权限框。
    static func wantsNotifications(_ document: ScheduleDocument) -> Bool {
        document.reminders.shiftStartEnabled || document.reminders.clockOutEnabled
            || (document.reminders.countdownEnabled && document.countdowns.contains { $0.remind && $0.kind == .countdown })
            || document.events.contains { $0.reminderMinutes != nil }
    }

    /// 请求通知权限。已经决定过（允许或拒绝）就不会再弹框，直接返回当前结果。
    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        }
    }

    /// 现在有没有权限，给提醒设置页显示用。
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus == .denied
    }

    /// 合并重排：连续改数据只在停下来半秒后排一次。
    static func scheduleRebuild(for document: ScheduleDocument) {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            await rebuild(for: document)
        }
    }

    static func rebuild(for document: ScheduleDocument) async {
        let center = UNUserNotificationCenter.current()
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(prefix) || $0.hasPrefix(legacyPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)

        guard wantsNotifications(document) else { return }
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else { return }

        let calendar = ScheduleCalendar.calendar
        for item in ReminderPlanner.plan(document, now: Date()) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.fireDate)
            let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
            let request = UNNotificationRequest(identifier: prefix + item.id, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }
}

/// App 在前台时也把提醒横幅弹出来（系统默认前台不显示）。
final class ForegroundNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ForegroundNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
