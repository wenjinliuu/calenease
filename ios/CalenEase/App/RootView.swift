import SwiftUI

/// 主页面：日历、事项、工时、设置。关掉排班功能时工时页收起来。
/// 标签栏常驻：这三页之间来回切换很频繁，滚动时把它收起来反而要多点一次。
struct RootView: View {
    @Environment(ScheduleStore.self) private var store

    @State private var selection: MainTab = .calendar
    @State private var toast: ToastMessage?
    /// 已经在「事项」页时再点一次「事项」标签，就回到今天。
    @State private var agendaReset = 0

    /// 标签选中。点的就是当前这一页（再点一次）时，系统也会调这个 set。
    private var tabSelection: Binding<MainTab> {
        Binding(get: { selection }, set: { tab in
            if tab == selection, tab == .agenda { agendaReset += 1 }
            selection = tab
        })
    }

    var body: some View {
        @Bindable var observed = store
        TabView(selection: tabSelection) {
            Tab("日历", systemImage: "calendar", value: MainTab.calendar) {
                CalendarScreen()
            }
            Tab("事项", systemImage: "checklist", value: MainTab.agenda) {
                AgendaScreen(resetToken: agendaReset)
            }
            // 工时页只属于排班那一套；关掉排班功能的人没有工时可看，整页收起来
            if store.document.features.shiftsEnabled {
                Tab("工时", systemImage: "chart.bar.xaxis", value: MainTab.stats) {
                    StatsScreen()
                }
            }
            Tab("设置", systemImage: "gearshape", value: MainTab.settings) {
                SettingsScreen()
            }
        }
        .onChange(of: store.document.features.shiftsEnabled) { _, enabled in
            if !enabled && selection == .stats { selection = .calendar }
        }
        .sheet(isPresented: $observed.needsOnboarding) {
            OnboardingSheet()
                .interactiveDismissDisabled()
        }
        .environment(\.showToast, ShowToastAction { message in
            withAnimation(.spring(response: 0.36, dampingFraction: 0.8)) { toast = message }
        })
        .overlay(alignment: .bottom) {
            if let toast {
                ToastBanner(message: toast)
                    .padding(.bottom, 96)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: toast.id) {
                        try? await Task.sleep(for: .seconds(2.2))
                        withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
                    }
            }
        }
    }
}

enum MainTab: Hashable {
    case calendar, agenda, stats, settings
}

// MARK: - 第一次打开

/// 新装第一次打开问一句：倒班还是固定作息。固定作息的人把排班功能关掉，
/// 首页只剩日历、日程和倒数日，工时页也不出现。以后在设置里随时能改。
private struct OnboardingSheet: View {
    @Environment(ScheduleStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("你的上班方式是？")
                    .font(.title2.weight(.bold))
                Text("决定首页要不要显示班次。之后可以在「设置 › 功能」里随时切换。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            choice(title: "倒班 / 轮班",
                   detail: "白班夜班轮着上。排班、循环、工时统计、上下班提醒都打开。",
                   symbol: "arrow.triangle.2.circlepath",
                   tint: Palette.blue,
                   shifts: true)
            choice(title: "固定作息",
                   detail: "朝九晚五、跟着法定节假日休息。只用日历、日程和倒数日。",
                   symbol: "sun.max",
                   tint: Palette.orange,
                   shifts: false)
        }
        .padding(24)
        .presentationDetents([.height(400)])
        .presentationCornerRadius(28)
    }

    private func choice(title: String, detail: String, symbol: String, tint: Color, shifts: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) { store.completeOnboarding(shiftsEnabled: shifts) }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 44, height: 44)
                    .background(tint.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.headline).foregroundStyle(.primary)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 轻提示

struct ToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    var symbol: String = "checkmark.circle.fill"
}

struct ToastBanner: View {
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: message.symbol)
            Text(message.text).font(.subheadline.weight(.medium))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .floatingPill(interactive: false)
        .shadow(color: .black.opacity(0.12), radius: 12, y: 4)
    }
}

/// 让任意子视图弹提示，不必层层传闭包。
struct ShowToastAction {
    let handler: (ToastMessage) -> Void

    func callAsFunction(_ text: String, symbol: String = "checkmark.circle.fill") {
        handler(ToastMessage(text: text, symbol: symbol))
    }
}

private struct ShowToastKey: EnvironmentKey {
    static let defaultValue = ShowToastAction { _ in }
}

extension EnvironmentValues {
    var showToast: ShowToastAction {
        get { self[ShowToastKey.self] }
        set { self[ShowToastKey.self] = newValue }
    }
}
