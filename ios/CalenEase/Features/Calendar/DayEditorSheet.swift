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
///
/// 日程页本身就是「在这天新建日程」的表单，填了标题按「完成」就加上；
/// 这天已有的日程排在表单下面，点开编辑、左滑删除。
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
    @State private var eventTarget: EventEditorTarget?
    /// 日程页上正在填的新日程。
    @State private var newEvent: CalendarEvent
    @State private var newEventHasUntil = false

    private var document: ScheduleDocument { store.document }
    private var selectedShift: ShiftDefinition? { document.shift(draft.shiftId) }
    private var shiftsEnabled: Bool { document.features.shiftsEnabled }
    private var isShiftDirty: Bool { loaded && draft != original }

    private var canAddEvent: Bool { EventEditorSheet.canSave(newEvent) }

    init(date: String, initialSegment: DaySegment = .shift) {
        self.date = date
        self.initialSegment = initialSegment
        _segment = State(initialValue: initialSegment)
        _newEvent = State(initialValue: CalendarEvent(startDate: date))
    }

    var body: some View {
        NavigationStack {
            Group {
                if shiftsEnabled {
                    // 分段控件单独占一行，表单排在它下面——原来叠在表单上面，
                    // 「主要班次」这些分组的开头被两颗按钮压住了一截。
                    VStack(spacing: 0) {
                        segmentBar
                        TabView(selection: $segment) {
                            shiftPage.tag(DaySegment.shift)
                            eventsPage.tag(DaySegment.events)
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                    }
                } else {
                    eventsPage
                }
            }
            .background(Palette.grouped)
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isShiftDirty || canAddEvent ? "取消" : "关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(segment == .events && canAddEvent ? "添加" : "完成") {
                        var saved: [String] = []
                        if isShiftDirty && !draft.shiftId.isEmpty {
                            var record = draft
                            record.planned = true
                            store.save(record)
                            saved.append("排班")
                        }
                        if canAddEvent {
                            let event = EventEditorSheet.finalized(newEvent, hasUntil: newEventHasUntil,
                                                                   document: document)
                            store.saveEvent(event)
                            if event.reminderMinutes != nil {
                                Task { await NotificationScheduler.requestAuthorization() }
                            }
                            saved.append("日程")
                        }
                        if !saved.isEmpty {
                            showToast(saved == ["日程"] ? "已添加日程" : "已保存 \(date)",
                                      symbol: saved == ["日程"] ? "calendar.badge.checkmark" : "checkmark.circle.fill")
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
            .interactiveDismissDisabled(isShiftDirty || canAddEvent)
            .sensoryFeedback(.selection, trigger: segment)
        }
        // 两页统一一个高度：之前跟着内容走，没有日程的那页矮得只剩一条，切页时抽屉忽高忽低。
        .presentationDetents([.fraction(0.78), .large])
        .presentationDragIndicator(.visible)
    }

    private var segmentBar: some View {
        Picker("", selection: $segment.animation(.smooth(duration: 0.3))) {
            ForEach(DaySegment.allCases) { item in Text(item.rawValue).tag(item) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .padding(.horizontal, 16)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity)
        .background(Palette.grouped)
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

            if let shift = selectedShift, shift.countsAsWork, document.work.trackHours || !shift.isRest {
                hoursSection(shift)
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

            shiftReminderSection

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
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollContentBackground(.hidden)
    }

    // MARK: - 工时与当天时间

    /// 工时：班次已完成、这天的上下班时间（可以只改今天）、实际 / 计划工时。
    /// 改了上下班时间，工时按新的时长自动重算，仍然可以再用步进微调。
    private func hoursSection(_ shift: ShiftDefinition) -> some View {
        let trackHours = document.work.trackHours
        return Section {
            if trackHours {
                Toggle("班次已完成", isOn: $draft.completed)
            }
            if !shift.isRest {
                Toggle(isOn: customTimeBinding(shift).animation(.snappy(duration: 0.25))) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("只改这天的上下班时间")
                        Text(draft.hasCustomTime
                             ? "班次设置里是 \(shift.fullRange.isEmpty ? "未设时间" : shift.fullRange)"
                             : (shift.fullRange.isEmpty ? "照班次设置" : "照班次设置 \(shift.fullRange)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if draft.hasCustomTime {
                    DatePicker("上班", selection: timeBinding(\.startTime, shift: shift),
                               displayedComponents: [.hourAndMinute])
                    DatePicker("下班", selection: timeBinding(\.endTime, shift: shift),
                               displayedComponents: [.hourAndMinute])
                }
            }
            if trackHours {
                LabeledStepper(label: "实际 / 计划工时", value: $draft.hours, step: 0.5, range: 0...24)
                if needsManualOvertime {
                    LabeledStepper(label: "手动额外工时",
                                   value: Binding(get: { draft.manualOvertime ?? 0 },
                                                  set: { draft.manualOvertime = $0 }),
                                   step: 0.5, range: 0...24)
                }
            }
        } header: {
            Text(trackHours ? "工时" : "上下班时间")
        } footer: {
            if draft.hasCustomTime, let start = draft.startTime, let end = draft.endTime {
                Text(customTimeFooter(shift, start: start, end: end))
            }
        }
    }

    private func customTimeFooter(_ shift: ShiftDefinition, start: String, end: String) -> String {
        let crosses = (EventClock.minutes(end) ?? 0) <= (EventClock.minutes(start) ?? 0)
        var text = "\(start)–\(crosses ? "次日 " : "")\(end)"
        guard document.work.trackHours else { return text + "，上下班提醒也按这个时间。" }
        let hours = shift.hours(startTime: start, endTime: end)
        text += " 算 \(HoursFormatter.compact(hours)) 小时"
        let unpaid = shift.fullRange.isEmpty ? 0 : max(0, shift.duration - shift.defaultHours)
        if unpaid > 0 { text += "（照班次扣除休息 \(HoursFormatter.compact(unpaid)) 小时）" }
        if draft.secondaryShiftId != nil { text += "，另加次要班次工时" }
        return text + "。只影响这一天，班次设置不变。"
    }

    /// 打开：先按班次原来的时间填上；关上：回到班次设置，工时也恢复默认。
    private func customTimeBinding(_ shift: ShiftDefinition) -> Binding<Bool> {
        Binding(get: { draft.hasCustomTime }, set: { on in
            if on {
                draft.startTime = shift.startTime.isEmpty ? "09:00" : shift.startTime
                draft.endTime = shift.endTime.isEmpty ? "18:00" : shift.endTime
            } else {
                draft.startTime = nil
                draft.endTime = nil
            }
            recomputeHours(shift)
        })
    }

    private func timeBinding(_ keyPath: WritableKeyPath<DayRecord, String?>, shift: ShiftDefinition) -> Binding<Date> {
        Binding(get: {
            EventClock.date(key: date, time: draft[keyPath: keyPath] ?? "09:00")
        }, set: { value in
            draft[keyPath: keyPath] = EventClock.split(value).time
            recomputeHours(shift)
        })
    }

    /// 按当天实际上下班时间重算工时（加上次要班次的默认工时）。
    private func recomputeHours(_ shift: ShiftDefinition) {
        let primary: Double
        if let start = draft.startTime, let end = draft.endTime {
            primary = shift.hours(startTime: start, endTime: end)
        } else {
            primary = shift.defaultHours
        }
        draft.hours = min(24, primary + secondaryDefaultHours)
    }

    // MARK: - 提醒

    /// 班次页底部的提醒：开关和提前多久，就地改，不用再跑去设置里。
    private var shiftReminderSection: some View {
        let reminders = document.reminders
        return Section {
            Toggle(isOn: reminderBinding(\.shiftStartEnabled)) {
                Label("上班前提醒", systemImage: "alarm")
            }
            if reminders.shiftStartEnabled {
                Picker("提前", selection: reminderBinding(\.shiftStartMinutes)) {
                    ForEach([15, 30, 45, 60, 90, 120, 180], id: \.self) { minutes in
                        Text(ReminderPlanner.lead(minutes)).tag(minutes)
                    }
                }
            }
            Toggle(isOn: reminderBinding(\.clockOutEnabled)) {
                Label("下班打卡提醒", systemImage: "figure.walk.departure")
            }
            if reminders.clockOutEnabled {
                Picker("下班后", selection: reminderBinding(\.clockOutMinutes)) {
                    ForEach([0, 5, 10, 15, 30], id: \.self) { minutes in
                        Text(minutes == 0 ? "准点" : ReminderPlanner.lead(minutes)).tag(minutes)
                    }
                }
            }
        } header: {
            Text("提醒")
        } footer: {
            Text(reminderFooter)
        }
    }

    private var reminderFooter: String {
        guard let shift = selectedShift, !shift.isRest, !shift.startTime.isEmpty else {
            return "对所有排了班的日子生效，休息日不提醒。按班次单独开关在「设置 › 提醒」。"
        }
        var parts: [String] = []
        let reminders = document.reminders
        // 这天单独改过上下班时间的，按改过的算
        let times = draft.times(for: shift)
        let startMinutes = EventClock.minutes(times.start)
        if reminders.shiftStartEnabled, !reminders.shiftStartExcluded.contains(shift.id), let start = startMinutes {
            parts.append("这天 \(EventClock.text(start - reminders.shiftStartMinutes)) 提醒上班")
        }
        if reminders.clockOutEnabled, let end = EventClock.minutes(times.end) {
            let time = EventClock.text((end + reminders.clockOutMinutes) % (24 * 60))
            let crosses = draft.hasCustomTime ? end <= (startMinutes ?? 0) : shift.crossesMidnight
            parts.append("\(crosses ? "次日 " : "")\(time) 提醒打卡")
        }
        let summary = parts.isEmpty ? "" : parts.joined(separator: "，") + "。"
        return summary + "对所有排了班的日子生效，按班次单独开关在「设置 › 提醒」。"
    }

    /// 改提醒设置；打开任何一项时顺手请求通知权限。
    private func reminderBinding<Value>(_ keyPath: WritableKeyPath<ReminderSettings, Value>) -> Binding<Value> {
        Binding(get: { document.reminders[keyPath: keyPath] }, set: { newValue in
            withAnimation(.snappy(duration: 0.25)) {
                store.updateReminders { $0[keyPath: keyPath] = newValue }
            }
            if (newValue as? Bool) == true {
                Task { await NotificationScheduler.requestAuthorization() }
            }
        })
    }

    // MARK: - 日程页

    /// 日程页就是「在这天新建日程」：直接填表单，按右上角「添加」。
    /// 这天已有的日程排在最后，点一下编辑，左滑删除。
    private var eventsPage: some View {
        let occurrences = store.occurrences(on: date)
        return EventEditorForm(draft: $newEvent, hasUntil: $newEventHasUntil) {
            if !occurrences.isEmpty {
                Section {
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
                } header: {
                    Text("这天已有 \(occurrences.count) 条日程")
                } footer: {
                    if occurrences.contains(where: { $0.event.recurrence.isRepeating }) {
                        Text("重复日程左滑删除的只是这一次。")
                    }
                }
            }
        }
        .contentMargins(.top, 4, for: .scrollContent)
        .scrollContentBackground(.hidden)
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
        // 换了班次，这天单独改过的上下班时间就不作数了
        if draft.shiftId != shift.id {
            draft.startTime = nil
            draft.endTime = nil
        }
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
        return system == .manual || system == .irregular || system == .hourly
            || (system == .custom && document.work.customRule == .manual)
    }

    private func loadDraft() {
        guard !loaded else { return }
        // 新日程按设置里的默认提醒和下一个整点填好时间
        newEvent = EventEditorTarget.new(on: date, reminders: document.reminders).event
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
