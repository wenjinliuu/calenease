import SwiftUI

/// 抽屉里的两页。
enum DaySegment: String, CaseIterable, Identifiable, Hashable {
    case shift = "排班"
    case events = "日程"
    var id: String { rawValue }
}

/// 点两下格子弹出来的大抽屉：上面分段切「排班 | 日程」，左右滑也能切。
///
/// 排班页改的只是当天，不会打断后续循环——要改未来请用"循环排班"。
/// 排班页只有真改了才保存，光进来看一眼、切到日程页加一条日程，不会平白多出一条排班记录。
struct DayEditorSheet: View {
    let date: String
    let initialSegment: DaySegment

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var segment: DaySegment = .shift
    @State private var draft = DayRecord(date: "", shiftId: "", hours: 0)
    /// 打开时的样子，用来判断改没改。
    @State private var original = DayRecord(date: "", shiftId: "", hours: 0)
    @State private var loaded = false
    /// 次要班次那一块展开了没有。默认收着，只露一个「添加次要班次」。
    @State private var showsSecondary = false
    /// 每一页表单实际要多高。抽屉按当前页定高度。
    @State private var pageHeights: [DaySegment: CGFloat] = [:]
    @State private var eventTarget: EventEditorTarget?

    private var document: ScheduleDocument { store.document }
    private var selectedShift: ShiftDefinition? { document.shift(draft.shiftId) }
    private var shiftsEnabled: Bool { document.features.shiftsEnabled }
    private var isShiftDirty: Bool { loaded && draft != original }

    /// 分段控件那一条的高度，两页的表单都往下让出这么多。
    private static let segmentBarHeight: CGFloat = 48

    init(date: String, initialSegment: DaySegment = .shift) {
        self.date = date
        self.initialSegment = initialSegment
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        NavigationStack {
            Group {
                if shiftsEnabled {
                    TabView(selection: $segment) {
                        shiftPage.tag(DaySegment.shift)
                        eventsPage.tag(DaySegment.events)
                    }
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .overlay(alignment: .top) { segmentBar }
                } else {
                    eventsPage
                }
            }
            .background(Palette.grouped)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isShiftDirty ? "取消" : "关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        if isShiftDirty && !draft.shiftId.isEmpty {
                            var record = draft
                            record.planned = true
                            store.save(record)
                            showToast("已保存 \(date)")
                        }
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
            .sheet(item: $eventTarget) { target in
                EventEditorSheet(target: target)
            }
            .onAppear {
                loadDraft()
                if !shiftsEnabled { segment = .events }
            }
            .sensoryFeedback(.selection, trigger: segment)
        }
        // 抽屉高度跟着当前这一页的内容走；内容比屏幕还高时系统封顶到全屏，表单自己滚动。
        .presentationDetents([detentHeight.map { PresentationDetent.height($0) } ?? .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
    }

    private var detentHeight: CGFloat? {
        let key = shiftsEnabled ? segment : .events
        return pageHeights[key]
    }

    private var segmentBar: some View {
        Picker("", selection: $segment.animation(.smooth(duration: 0.3))) {
            ForEach(DaySegment.allCases) { item in Text(item.rawValue).tag(item) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .frame(height: Self.segmentBarHeight, alignment: .top)
        .frame(maxWidth: .infinity)
        .background(Palette.grouped)
    }

    /// 量表单内容的总高度（含导航栏、分段条和底部安全区）。
    private func measured(_ page: DaySegment) -> PageHeightReader {
        PageHeightReader { height in
            withAnimation(.smooth(duration: 0.3)) { pageHeights[page] = height }
        }
    }

    // MARK: - 排班页

    private var shiftPage: some View {
        Form {
            Section("主要班次") {
                ShiftPickerGrid(shifts: document.orderedShifts,
                                selection: draft.shiftId) { shift in
                    selectPrimary(shift)
                }
            }

            secondarySection

            if !document.tags.isEmpty {
                Section("职责标签 · 可多选") {
                    TagPickerFlow(tags: document.tags, selection: $draft.tagIds)
                }
            }

            if document.work.trackHours, selectedShift?.countsAsWork == true {
                Section("工时") {
                    Toggle("班次已完成", isOn: $draft.completed)
                    LabeledStepper(label: "实际 / 计划工时", value: $draft.hours, step: 0.5, range: 0...24)
                    if needsManualOvertime {
                        LabeledStepper(label: "手动额外工时",
                                       value: Binding(get: { draft.manualOvertime ?? 0 },
                                                      set: { draft.manualOvertime = $0 }),
                                       step: 0.5, range: 0...24)
                    }
                }
            }

            Section {
                TextField("这一天需要记点什么？", text: Binding(get: { draft.note ?? "" },
                                                    set: { draft.note = $0.isEmpty ? nil : $0 }),
                          axis: .vertical)
                    .lineLimit(1...4)
            } header: {
                Text("备注")
            } footer: {
                Text("这里只修改当天，不会改变后续循环。要改变未来，请使用「循环排班」。")
            }

            if store.record(on: date) != nil {
                Section {
                    Button(role: .destructive) {
                        store.clearDay(date)
                        showToast("已清空当天", symbol: "trash")
                        dismiss()
                    } label: {
                        Label("清空这一天的排班", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
        }
        .contentMargins(.top, shiftsEnabled ? Self.segmentBarHeight - 20 : 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .modifier(measured(.shift))
    }

    // MARK: - 日程页

    private var eventsPage: some View {
        let occurrences = store.occurrences(on: date)
        return Form {
            Section {
                if occurrences.isEmpty {
                    Text("这天还没有日程")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 10)
                } else {
                    ForEach(occurrences) { occurrence in
                        Button { eventTarget = .edit(occurrence) } label: {
                            EventRow(occurrence: occurrence, day: date)
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                if occurrence.event.recurrence.isRepeating {
                                    store.excludeOccurrence(eventId: occurrence.event.id, on: occurrence.startKey)
                                } else {
                                    store.deleteEvent(id: occurrence.event.id)
                                }
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
            } footer: {
                if occurrences.contains(where: { $0.event.recurrence.isRepeating }) {
                    Text("重复日程左滑删除的只是这一次。")
                }
            }

            Section {
                Button {
                    eventTarget = .new(on: date, reminders: document.reminders)
                } label: {
                    Label("新建日程", systemImage: "plus.circle.fill")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .contentMargins(.top, shiftsEnabled ? Self.segmentBarHeight - 20 : 0, for: .scrollContent)
        .scrollContentBackground(.hidden)
        .modifier(measured(.events))
    }

    // MARK: - 次要班次

    /// 次要班次：默认只有一个加号按钮，点开才出现一整套班次可选，和主要班次一样的样子。
    @ViewBuilder
    private var secondarySection: some View {
        if showsSecondary {
            Section {
                ShiftPickerGrid(shifts: document.orderedShifts.filter { $0.id != draft.shiftId },
                                selection: draft.secondaryShiftId ?? "") { shift in
                    selectSecondary(shift)
                }
                Button(role: .destructive) {
                    withAnimation(.snappy(duration: 0.28)) { removeSecondary() }
                } label: {
                    Label("去掉次要班次", systemImage: "minus.circle")
                        .foregroundStyle(.red)
                }
            } header: {
                Text("次要班次")
            }
        } else {
            Section {
                Button {
                    withAnimation(.snappy(duration: 0.28)) { showsSecondary = true }
                } label: {
                    Label("添加次要班次", systemImage: "plus.circle.fill")
                }
            }
        }
    }

    /// 换主要班次：工时按「主要 + 次要」两个班次的默认工时重算。
    private func selectPrimary(_ shift: ShiftDefinition) {
        draft.shiftId = shift.id
        if draft.secondaryShiftId == shift.id { draft.secondaryShiftId = nil }
        draft.hours = min(24, shift.defaultHours + secondaryDefaultHours)
    }

    /// 选次要班次：把它的默认工时加进当天工时；再点一次同一个就取消。
    private func selectSecondary(_ shift: ShiftDefinition) {
        let previous = secondaryDefaultHours
        if draft.secondaryShiftId == shift.id {
            draft.secondaryShiftId = nil
            draft.hours = max(0, draft.hours - previous)
            return
        }
        draft.secondaryShiftId = shift.id
        draft.hours = min(24, max(0, draft.hours - previous + shift.defaultHours))
    }

    private func removeSecondary() {
        draft.hours = max(0, draft.hours - secondaryDefaultHours)
        draft.secondaryShiftId = nil
        showsSecondary = false
    }

    private var secondaryDefaultHours: Double {
        draft.secondaryShiftId.flatMap { document.shift($0) }?.defaultHours ?? 0
    }

    /// 标题写「9月9日 周三」，节日缀上节日名，放假 / 调休再缀「休」「班」。
    private var titleText: String {
        guard let parts = ScheduleCalendar.components(from: date) else { return date }
        let weekday = ScheduleCalendar.weekdaySymbols[ScheduleCalendar.weekdayIndex(date)]
        var text = "\(parts.month + 1)月\(parts.day)日 周\(weekday)"
        if let festival = Festivals.festival(on: date) { text += " · \(festival.name)" }
        switch store.holidays.adjustment(on: date) {
        case .off: text += " · 休"
        case .work: text += " · 班"
        case nil: break
        }
        return text
    }

    /// 不定时工时和手动记录制下才需要逐日登记加班。
    private var needsManualOvertime: Bool {
        guard document.work.trackOvertime else { return false }
        let system = document.work.system
        return system == .manual || system == .irregular
            || (system == .custom && document.work.customRule == .manual)
    }

    private func loadDraft() {
        guard !loaded else { return }
        if let existing = store.record(on: date) {
            draft = existing
            // 次要班次指向的班次已经删掉了就当没有。
            if let secondary = existing.secondaryShiftId, document.shift(secondary) == nil {
                draft.secondaryShiftId = nil
            }
            showsSecondary = draft.secondaryShiftId != nil
        } else {
            let fallback = document.orderedShifts.first
            draft = DayRecord(date: date,
                              shiftId: fallback?.id ?? "",
                              hours: fallback?.defaultHours ?? 0,
                              source: .manual)
        }
        original = draft
        loaded = true
    }
}

/// 量一个表单的总高度：内容 + 上下内边距（导航栏、分段条让出的边距、底部安全区）。
private struct PageHeightReader: ViewModifier {
    let onChange: (CGFloat) -> Void

    func body(content: Content) -> some View {
        content.onScrollGeometryChange(for: CGFloat.self) { geometry in
            (geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom).rounded(.up)
        } action: { _, height in
            guard height > 0 else { return }
            onChange(height)
        }
    }
}

/// 班次选择网格，日编辑和批量修改共用。
struct ShiftPickerGrid: View {
    let shifts: [ShiftDefinition]
    let selection: String
    let onSelect: (ShiftDefinition) -> Void

    private let columns = [GridItem(.adaptive(minimum: 92), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(shifts) { shift in
                Button {
                    onSelect(shift)
                } label: {
                    HStack(spacing: 8) {
                        ShiftOrb(shift: shift, size: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shift.name)
                                .font(.footnote.weight(.semibold))
                                .lineLimit(1)
                            if !shift.fullRange.isEmpty {
                                Text(shift.fullRange)
                                    .font(.system(size: 9.5))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(shift.tint.opacity(selection == shift.id ? 0.20 : 0.06))
                    }
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(selection == shift.id ? shift.tint : .clear, lineWidth: 1.5)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 标签多选。
struct TagPickerFlow: View {
    let tags: [DutyTag]
    @Binding var selection: [String]

    private let columns = [GridItem(.adaptive(minimum: 82), spacing: 8)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(tags) { tag in
                let picked = selection.contains(tag.id)
                Button {
                    if picked { selection.removeAll { $0 == tag.id } } else { selection.append(tag.id) }
                } label: {
                    Text(tag.name)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(picked ? .white : tag.tint)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 7)
                        .background(picked ? AnyShapeStyle(tag.tint) : AnyShapeStyle(tag.tint.opacity(0.14)),
                                    in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 2)
    }
}

/// 带步进的数值行，工时这类小数用。
struct LabeledStepper: View {
    let label: String
    @Binding var value: Double
    var step: Double = 0.5
    var range: ClosedRange<Double> = 0...24
    var unit: String = "小时"

    var body: some View {
        Stepper(value: $value, in: range, step: step) {
            HStack {
                Text(label)
                Spacer()
                Text("\(HoursFormatter.compact(value)) \(unit)")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
    }
}
