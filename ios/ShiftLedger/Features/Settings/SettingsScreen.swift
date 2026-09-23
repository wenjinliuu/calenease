import SwiftUI

/// 设置页：班次与标签、工时制度、日历显示、基本工时修正、备份与关于。
struct SettingsScreen: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(AppPreferences.self) private var preferences
    @Environment(\.showToast) private var showToast

    @State private var shiftPendingDeletion: ShiftDefinition?
    @State private var editingShift: ShiftDefinition?
    @State private var editingTag: DutyTag?
    @State private var isCreatingShift = false
    @State private var isCreatingTag = false

    private var document: ScheduleDocument { store.document }

    var body: some View {
        NavigationStack {
            Form {
                workSection
                shiftsSection
                tagsSection
                displaySection
                appearanceSection

                Section("工时修正与备份") {
                    NavigationLink {
                        MonthlyTargetsView()
                    } label: {
                        Label("每月基本工时", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        BackupView()
                    } label: {
                        HStack {
                            Label("备份与恢复", systemImage: "arrow.up.arrow.down.circle")
                            if preferences.backupNeedsAttention {
                                Spacer()
                                Text("建议导出")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(Palette.orange)
                            }
                        }
                    }
                }

                Section {
                    NavigationLink {
                        AboutView()
                    } label: {
                        Label("关于循环班表", systemImage: "info.circle")
                    }
                }
            }
            .pageBackground()
            .navigationTitle("设置")
            .sheet(item: $editingShift) { shift in
                ShiftEditorView(shift: shift)
            }
            .sheet(isPresented: $isCreatingShift) {
                ShiftEditorView(shift: nil)
            }
            .sheet(item: $editingTag) { tag in
                TagEditorView(tag: tag)
            }
            .sheet(isPresented: $isCreatingTag) {
                TagEditorView(tag: nil)
            }
            .confirmationDialog(deletionPrompt,
                                isPresented: Binding(get: { shiftPendingDeletion != nil },
                                                     set: { if !$0 { shiftPendingDeletion = nil } }),
                                titleVisibility: .visible) {
                Button("删除班次", role: .destructive) {
                    guard let shift = shiftPendingDeletion else { return }
                    store.deleteShift(shift)
                    showToast("班次已删除", symbol: "trash")
                    shiftPendingDeletion = nil
                }
                Button("取消", role: .cancel) { shiftPendingDeletion = nil }
            }
            .sensoryFeedback(.success, trigger: document.shifts.count)
        }
    }


    // MARK: - 班次

    private var shiftsSection: some View {
        Section {
            ForEach(document.orderedShifts) { shift in
                Button {
                    editingShift = shift
                } label: {
                    HStack(spacing: 12) {
                        ShiftOrb(shift: shift, size: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(shift.name).foregroundStyle(.primary)
                            Text(detail(for: shift))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                // 不加 .plain 的话整行会被按钮的强调色染蓝
                .buttonStyle(.plain)
                .contextMenu {
                    Button { editingShift = shift } label: { Label("编辑班次", systemImage: "pencil") }
                    Button { duplicate(shift) } label: { Label("复制一份", systemImage: "plus.square.on.square") }
                    if shift.id != ShiftID.rest {
                        Button(role: .destructive) { shiftPendingDeletion = shift } label: {
                            Label("删除班次", systemImage: "trash")
                        }
                    }
                }
                .swipeActions(edge: .trailing) {
                    if shift.id != ShiftID.rest {
                        Button(role: .destructive) { shiftPendingDeletion = shift } label: {
                            Label("删除", systemImage: "trash")
                        }
                    }
                    Button { editingShift = shift } label: { Label("编辑", systemImage: "pencil") }
                        .tint(Palette.blue)
                }
            }
            Button {
                isCreatingShift = true
            } label: {
                Label("新增班次", systemImage: "plus.circle")
            }
        } header: {
            Text("班次")
        } footer: {
            Text("名称、简称、颜色、时间、跨天、休息属性和默认工时都可以改。")
        }
    }

    private var deletionPrompt: String {
        guard let shift = shiftPendingDeletion else { return "" }
        let used = store.usageCount(of: shift)
        return used > 0
            ? "「\(shift.name)」已排了 \(used) 天，删除会一并清空这些天。"
            : "删除「\(shift.name)」？"
    }

    /// 以现有班次为模板加一个新班次，比从空白开始快。
    private func duplicate(_ shift: ShiftDefinition) {
        var copy = shift
        copy.id = ShiftCatalog.makeId("shift")
        copy.name = "\(shift.name) 副本"
        copy.legacyType = nil
        store.saveShift(copy)
        editingShift = copy
    }

    private func detail(for shift: ShiftDefinition) -> String {
        var parts: [String] = []
        if !shift.fullRange.isEmpty { parts.append(shift.fullRange) }
        if shift.isRest {
            parts.append("休息")
        } else if document.work.trackHours {
            parts.append("默认 \(HoursFormatter.hours(shift.defaultHours))")
        }
        return parts.joined(separator: " · ")
    }

    // MARK: - 标签

    private var tagsSection: some View {
        Section {
            if document.tags.isEmpty {
                Text("还没有职责标签。标签和班次相互独立，一天可以挂多个。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(document.tags) { tag in
                Button {
                    editingTag = tag
                } label: {
                    HStack(spacing: 12) {
                        Circle().fill(tag.tint).frame(width: 14, height: 14)
                        Text(tag.name).foregroundStyle(.primary)
                        Spacer()
                        Text(tag.shortName).font(.caption).foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .contextMenu {
                    Button { editingTag = tag } label: { Label("编辑标签", systemImage: "pencil") }
                    Button(role: .destructive) { store.deleteTag(tag) } label: {
                        Label("删除标签", systemImage: "trash")
                    }
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        store.deleteTag(tag)
                        showToast("标签已删除", symbol: "trash")
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    Button { editingTag = tag } label: { Label("编辑", systemImage: "pencil") }
                        .tint(Palette.blue)
                }
            }
            Button {
                isCreatingTag = true
            } label: {
                Label("新增标签", systemImage: "plus.circle")
            }
        } header: {
            Text("职责标签")
        }
    }

    // MARK: - 工时

    private var workSection: some View {
        Section {
            Toggle("统计工时与加班", isOn: Binding(
                get: { document.work.trackHours },
                set: { enabled in
                    store.update { document in
                        document.work.trackHours = enabled
                        document.work.trackOvertime = enabled
                    }
                }
            ))

            if document.work.trackHours {
                Picker("工时制度", selection: Binding(
                    get: { document.work.system },
                    set: { system in
                        store.update { document in
                            document.work.system = system
                            // 综合计算工时固定按月结算，和 web 版一致
                            if system == .comprehensive { document.work.period = .month }
                        }
                    }
                )) {
                    ForEach(WorkSystem.allCases) { system in
                        Text(system.label).tag(system)
                    }
                }
                Text(document.work.system.caption)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if document.work.system == .comprehensive {
                    Picker("结算周期", selection: bind(\.period)) {
                        ForEach([StatisticsPeriod.week, .month, .quarter, .halfYear, .year]) { period in
                            Text(period.label).tag(period)
                        }
                    }
                    Picker("年度起始月", selection: Binding(
                        get: { document.work.annualStartMonth },
                        set: { month in store.update { $0.work.annualStartMonth = month } }
                    )) {
                        ForEach(1...12, id: \.self) { month in
                            Text("\(month)月").tag(month)
                        }
                    }
                }

                if document.work.system == .standard {
                    Toggle("按每日标准判定", isOn: bind(\.standardDailyEnabled))
                    if document.work.standardDailyEnabled {
                        LabeledStepper(label: "每日标准工时", value: bind(\.dailyStandard), step: 0.5, range: 0...24)
                    }
                    Toggle("按每周标准判定", isOn: bind(\.standardWeeklyEnabled))
                    if document.work.standardWeeklyEnabled {
                        LabeledStepper(label: "每周标准工时", value: bind(\.weeklyStandard), step: 1, range: 0...80)
                    }
                }

                if document.work.system == .custom {
                    Picker("判定口径", selection: bind(\.customRule)) {
                        ForEach(CustomOvertimeRule.allCases) { rule in
                            Text(rule.label).tag(rule)
                        }
                    }
                    if document.work.customRule != .manual {
                        LabeledStepper(label: "阈值", value: bind(\.customThreshold), step: 1, range: 0...400)
                    }
                }

                Picker("加班兑现方式", selection: bind(\.compensation)) {
                    ForEach(CompensationMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
            }
        } header: {
            Text("工时与加班")
        } footer: {
            Text("改班次默认工时时，仍按旧默认值排的日子会一起更新；单独调过工时的那些天保持不变。工时为个人预估，最终以公司考勤记录和适用制度为准。")
        }
    }

    /// 把 `document.work` 的某个字段变成可绑定值，改动直接落进 store。
    private func bind<Value>(_ keyPath: WritableKeyPath<WorkSettings, Value>) -> Binding<Value> {
        Binding(
            get: { document.work[keyPath: keyPath] },
            set: { newValue in store.update { $0.work[keyPath: keyPath] = newValue } }
        )
    }

    // MARK: - 显示

    private var displaySection: some View {
        Section {
            Toggle("显示班次简称", isOn: displayBind(\.showShift))
            Toggle("显示职责标签", isOn: displayBind(\.showTags))
            Toggle("显示班次时间", isOn: displayBind(\.showShiftTime))
            Toggle("显示当日工时", isOn: displayBind(\.showHours))
            Toggle("显示农历", isOn: displayBind(\.showLunar))
            Toggle("显示放假与调休", isOn: displayBind(\.showHolidays))
        } header: {
            Text("日历显示")
        }
    }

    private func displayBind(_ keyPath: WritableKeyPath<CalendarDisplaySettings, Bool>) -> Binding<Bool> {
        Binding(
            get: { document.display[keyPath: keyPath] },
            set: { newValue in store.update { $0.display[keyPath: keyPath] = newValue } }
        )
    }

    private var appearanceSection: some View {
        Section("外观") {
            Picker("主题", selection: Binding(
                get: { preferences.appearance },
                set: { preferences.appearance = $0 }
            )) {
                ForEach(AppPreferences.Appearance.allCases) { item in
                    Label(item.label, systemImage: item.symbol).tag(item)
                }
            }
        }
    }
}
