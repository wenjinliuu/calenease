import SwiftUI

extension AccentHex {
    /// 日程取色盘。挑色相分得开的十二个，色条做成淡底之后也认得出。
    static let eventPalette = [vividCyan, navy, spring, vividOrange, lemon, peach,
                               lavender, mint, coral, caramel, rose, purple]
}

/// 打开日程编辑器要带的东西。`occurrenceDate` 是从哪一次点进来的（重复日程「只删这一次」要用）。
struct EventEditorTarget: Identifiable {
    let id = UUID()
    var event: CalendarEvent
    var occurrenceDate: String?
    var isNew: Bool

    /// 在某一天新建。`startMinute` 给了就是定时日程（时间轴上点空白处），否则按下一个整点。
    static func new(on date: String, startMinute: Int? = nil, reminders: ReminderSettings, color: String? = nil) -> Self {
        let start = startMinute ?? min(22 * 60, (Calendar.current.component(.hour, from: Date()) + 1) * 60)
        let end = min(start + 60, 23 * 60 + 59)
        var event = CalendarEvent(startDate: date,
                                  startTime: EventClock.text(start),
                                  endTime: EventClock.text(end),
                                  reminderMinutes: reminders.eventDefaultMinutes)
        if let color { event.color = color }
        return EventEditorTarget(event: event, occurrenceDate: date, isNew: true)
    }

    static func edit(_ occurrence: EventOccurrence) -> Self {
        EventEditorTarget(event: occurrence.event, occurrenceDate: occurrence.startKey, isNew: false)
    }
}

/// 「HH:mm」和分钟数互换。
enum EventClock {
    static func minutes(_ text: String) -> Int? { ReminderPlanner.minutes(of: text) }

    static func text(_ minutes: Int) -> String {
        let clamped = max(0, min(24 * 60 - 1, minutes))
        return String(format: "%02d:%02d", clamped / 60, clamped % 60)
    }

    static func date(key: String, time: String) -> Date {
        let base = ScheduleCalendar.date(from: key) ?? Date()
        return ScheduleCalendar.calendar.date(byAdding: .minute, value: minutes(time) ?? 0, to: base) ?? base
    }

    static func split(_ date: Date) -> (key: String, time: String) {
        let parts = ScheduleCalendar.calendar.dateComponents([.hour, .minute], from: date)
        return (ScheduleCalendar.key(date), text((parts.hour ?? 0) * 60 + (parts.minute ?? 0)))
    }
}

/// 新建 / 编辑一条日程。
struct EventEditorSheet: View {
    let target: EventEditorTarget

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var draft: CalendarEvent
    @State private var hasUntil: Bool
    @State private var isConfirmingDelete = false
    @FocusState private var titleFocused: Bool

    init(target: EventEditorTarget) {
        self.target = target
        _draft = State(initialValue: target.event)
        _hasUntil = State(initialValue: target.event.recurrence.until != nil)
    }

    private var document: ScheduleDocument { store.document }
    private var shiftsEnabled: Bool { document.features.shiftsEnabled }
    private var workShifts: [ShiftDefinition] { document.orderedShifts.filter { !$0.isRest } }

    private var repeatKinds: [EventRecurrence.Kind] {
        EventRecurrence.Kind.allCases.filter { $0 != .shift || (shiftsEnabled && !workShifts.isEmpty) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("标题", text: $draft.title)
                        .font(.headline)
                        .focused($titleFocused)
                        .submitLabel(.done)
                    ColorPaletteRow(palette: AccentHex.eventPalette, selection: $draft.color)
                    SymbolPickerRow(selection: $draft.symbol, tint: draft.color)
                }

                Section {
                    Toggle("全天", isOn: $draft.isAllDay.animation(.snappy(duration: 0.25)))
                    DatePicker("开始", selection: startBinding,
                               displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                    DatePicker("结束", selection: endBinding, in: startValue...,
                               displayedComponents: draft.isAllDay ? [.date] : [.date, .hourAndMinute])
                }
                .environment(\.locale, Locale(identifier: "zh_CN"))

                repeatSection

                Section("提醒") {
                    Picker("提醒", selection: $draft.reminderMinutes) {
                        Text("不提醒").tag(Int?.none)
                        if draft.isAllDay {
                            Text("当天 \(document.reminders.allDayEventTime)").tag(Int?.some(0))
                            Text("前一天 \(document.reminders.allDayEventTime)").tag(Int?.some(1440))
                        } else {
                            ForEach([0, 5, 10, 15, 30, 60, 120, 1440], id: \.self) { minutes in
                                Text(Self.reminderLabel(minutes)).tag(Int?.some(minutes))
                            }
                        }
                    }
                }

                Section("地点与链接") {
                    HStack(spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        TextField("地点", text: optionalText(\.location))
                        if let mapURL = Self.mapURL(draft.location) {
                            Link(destination: mapURL) {
                                Image(systemName: "map")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("在地图中打开")
                        }
                    }
                    HStack(spacing: 10) {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                            .frame(width: 22)
                        TextField("链接（会议、网页）", text: optionalText(\.url))
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        if let link = Self.webURL(draft.url) {
                            Link(destination: link) {
                                Image(systemName: "arrow.up.right.square")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("打开链接")
                        }
                    }
                }

                Section("备注") {
                    TextField("要带的东西、注意事项……", text: Binding(get: { draft.note ?? "" },
                                                        set: { draft.note = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(1...5)
                }

                if !target.isNew {
                    Section {
                        Button(role: .destructive) {
                            if target.event.recurrence.isRepeating && target.occurrenceDate != nil {
                                isConfirmingDelete = true
                            } else {
                                delete(all: true)
                            }
                        } label: {
                            Label("删除日程", systemImage: "trash").foregroundStyle(.red)
                        }
                    } footer: {
                        if target.event.recurrence.isRepeating {
                            Text("修改会作用于这条日程的每一次重复。")
                        }
                    }
                }
            }
            .pageBackground()
            .navigationTitle(target.isNew ? "新建日程" : "编辑日程")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存", action: save)
                        .disabled(draft.title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("这是重复日程", isPresented: $isConfirmingDelete, titleVisibility: .visible) {
                Button("只删除这一次", role: .destructive) { delete(all: false) }
                Button("删除全部重复", role: .destructive) { delete(all: true) }
                Button("取消", role: .cancel) {}
            }
            .onAppear { if target.isNew { titleFocused = true } }
            .onChange(of: draft.isAllDay) { _, allDay in
                // 全天和定时的提醒选项不一样，切换时换成对应的默认值
                if allDay {
                    draft.reminderMinutes = draft.reminderMinutes == nil ? nil : 0
                } else {
                    draft.reminderMinutes = draft.reminderMinutes == nil ? nil : document.reminders.eventDefaultMinutes ?? 15
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    // MARK: - 重复

    @ViewBuilder
    private var repeatSection: some View {
        Section("重复") {
            Picker("重复", selection: $draft.recurrence.kind.animation(.snappy(duration: 0.25))) {
                ForEach(repeatKinds) { kind in Text(kind.label).tag(kind) }
            }

            switch draft.recurrence.kind {
            case .weekly:
                WeekdayChips(selection: weekdaysBinding)
            case .interval:
                Stepper(value: $draft.recurrence.interval, in: 2...365) {
                    Text("每 \(draft.recurrence.interval) 天一次")
                }
            case .shift:
                Picker("班次", selection: shiftBinding) {
                    ForEach(workShifts) { shift in Text(shift.name).tag(shift.id) }
                }
                Picker("哪一天", selection: $draft.recurrence.shiftOffset) {
                    Text("班前一天").tag(-1)
                    Text("当天").tag(0)
                    Text("班后一天").tag(1)
                }
                .pickerStyle(.segmented)
            default:
                EmptyView()
            }

            if draft.recurrence.isRepeating {
                Toggle("设置结束日期", isOn: $hasUntil.animation(.snappy(duration: 0.25)))
                if hasUntil {
                    DatePicker("重复到", selection: untilBinding, in: startDay..., displayedComponents: [.date])
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                }
            }
        }
    }

    private var weekdaysBinding: Binding<[Int]> {
        Binding(get: {
            draft.recurrence.weekdays.isEmpty
                ? [ScheduleCalendar.weekdayIndex(draft.startDate)]
                : draft.recurrence.weekdays
        }, set: { draft.recurrence.weekdays = $0.sorted() })
    }

    private var shiftBinding: Binding<String> {
        Binding(get: { draft.recurrence.shiftId ?? workShifts.first?.id ?? "" },
                set: { draft.recurrence.shiftId = $0 })
    }

    private var startDay: Date { ScheduleCalendar.date(from: draft.startDate) ?? Date() }

    private var untilBinding: Binding<Date> {
        Binding(get: {
            draft.recurrence.until.flatMap(ScheduleCalendar.date(from:))
                ?? ScheduleCalendar.calendar.date(byAdding: .month, value: 3, to: startDay) ?? startDay
        }, set: { draft.recurrence.until = ScheduleCalendar.key($0) })
    }

    // MARK: - 时间

    private var startValue: Date {
        EventClock.date(key: draft.startDate, time: draft.isAllDay ? "00:00" : draft.startTime)
    }

    private var endValue: Date {
        EventClock.date(key: draft.endDate, time: draft.isAllDay ? "00:00" : draft.endTime)
    }

    /// 改开始时间时整段平移，时长不变。
    private var startBinding: Binding<Date> {
        Binding(get: { startValue }, set: { newValue in
            let length = endValue.timeIntervalSince(startValue)
            let start = EventClock.split(newValue)
            let end = EventClock.split(newValue.addingTimeInterval(max(0, length)))
            draft.startDate = start.key
            draft.endDate = end.key
            if !draft.isAllDay {
                draft.startTime = start.time
                draft.endTime = end.time
            }
        })
    }

    private var endBinding: Binding<Date> {
        Binding(get: { endValue }, set: { newValue in
            let end = EventClock.split(max(newValue, startValue))
            draft.endDate = end.key
            if !draft.isAllDay { draft.endTime = end.time }
        })
    }

    private func optionalText(_ keyPath: WritableKeyPath<CalendarEvent, String?>) -> Binding<String> {
        Binding(get: { draft[keyPath: keyPath] ?? "" },
                set: { draft[keyPath: keyPath] = $0.isEmpty ? nil : $0 })
    }

    /// 「地图」里搜这个地点。
    static func mapURL(_ location: String?) -> URL? {
        guard let text = location?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let query = text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "maps://?q=\(query)")
    }

    /// 用户填的链接：没写协议的补上 https://。
    static func webURL(_ text: String?) -> URL? {
        guard var value = text?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
        if !value.contains("://") { value = "https://" + value }
        guard let url = URL(string: value), url.host() != nil || url.scheme != "https" else { return nil }
        return url
    }

    static func reminderLabel(_ minutes: Int) -> String {
        switch minutes {
        case 0: "开始时"
        case 1440: "提前 1 天"
        default: "提前 \(ReminderPlanner.lead(minutes))"
        }
    }

    // MARK: - 存取

    private func save() {
        var event = draft
        event.title = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if event.endDate < event.startDate { event.endDate = event.startDate }
        if !event.isAllDay, event.endDate == event.startDate, event.endTime < event.startTime {
            event.endTime = event.startTime
        }
        switch event.recurrence.kind {
        case .weekly where event.recurrence.weekdays.isEmpty:
            event.recurrence.weekdays = [ScheduleCalendar.weekdayIndex(event.startDate)]
        case .shift where event.recurrence.shiftId == nil:
            event.recurrence.shiftId = workShifts.first?.id
        default:
            break
        }
        if !event.recurrence.isRepeating || !hasUntil { event.recurrence.until = nil }
        event.location = event.location?.trimmingCharacters(in: .whitespacesAndNewlines)
        if event.location?.isEmpty == true { event.location = nil }
        event.url = Self.webURL(event.url)?.absoluteString
        if !event.recurrence.isRepeating { event.exceptions = [] }
        store.saveEvent(event)
        if event.reminderMinutes != nil {
            Task { await NotificationScheduler.requestAuthorization() }
        }
        showToast(target.isNew ? "已添加日程" : "已保存日程", symbol: "calendar.badge.checkmark")
        dismiss()
    }

    private func delete(all: Bool) {
        if all {
            store.deleteEvent(id: target.event.id)
        } else if let date = target.occurrenceDate {
            store.excludeOccurrence(eventId: target.event.id, on: date)
        }
        showToast(all ? "已删除日程" : "已删除这一次", symbol: "trash")
        dismiss()
    }
}

/// 一周七天的多选小圆。
struct WeekdayChips: View {
    @Binding var selection: [Int]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<7, id: \.self) { index in
                let picked = selection.contains(index)
                Button {
                    if picked {
                        // 至少留一天
                        if selection.count > 1 { selection.removeAll { $0 == index } }
                    } else {
                        selection.append(index)
                    }
                } label: {
                    Text(ScheduleCalendar.weekdaySymbols[index])
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(picked ? .white : .primary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(picked ? AnyShapeStyle(Palette.blue) : AnyShapeStyle(Palette.inset), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("周\(ScheduleCalendar.weekdaySymbols[index])")
                .accessibilityAddTraits(picked ? .isSelected : [])
            }
        }
        .padding(.vertical, 2)
    }
}

/// 日程列表里的一行：左边一道色条，标题，下面是时间和重复。
struct EventRow: View {
    let occurrence: EventOccurrence
    /// 这一行是在哪一天的列表里（跨天日程写「第 2 天」）。
    let day: String

    var body: some View {
        let event = occurrence.event
        let tone = Tone.event(event.color)
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(tone.solid)
                .frame(width: 4, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(detail)
                        .monospacedDigit()
                    if let location = event.location {
                        Label(location, systemImage: "mappin")
                            .labelStyle(.titleAndIcon)
                    }
                    if event.recurrence.isRepeating {
                        Image(systemName: "repeat")
                    }
                    if event.reminderMinutes != nil {
                        Image(systemName: "bell")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 38)
        .contentShape(Rectangle())
    }

    private var detail: String {
        let event = occurrence.event
        guard occurrence.isMultiDay, let current = DayNumber.of(day) else { return event.timeLabel }
        let index = current - occurrence.start + 1
        let total = occurrence.end - occurrence.start + 1
        return "\(event.isAllDay ? "全天" : event.timeLabel) · 第 \(index)/\(total) 天"
    }
}

/// 事项页时间线上那颗圆里的图标。
enum EventSymbols {
    static let fallback = "calendar"
    static let all = ["calendar", "alarm", "sun.max", "briefcase", "cup.and.saucer", "fork.knife",
                      "figure.run", "dumbbell", "book", "brain.head.profile", "cart", "car",
                      "airplane", "house", "heart", "gift", "birthday.cake", "stethoscope",
                      "pills", "phone", "person.2", "bed.double", "leaf", "pawprint",
                      "music.note", "gamecontroller", "graduationcap", "bolt"]
}

/// 横向一排图标，点一下选中，再点一下取消（回到默认图标）。
struct SymbolPickerRow: View {
    @Binding var selection: String?
    let tint: String

    var body: some View {
        let tone = Tone.event(tint)
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(EventSymbols.all, id: \.self) { symbol in
                    let picked = (selection ?? EventSymbols.fallback) == symbol
                    Button {
                        selection = symbol == EventSymbols.fallback || picked ? nil : symbol
                    } label: {
                        Image(systemName: symbol)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(picked ? AnyShapeStyle(.white) : AnyShapeStyle(tone.ink))
                            .frame(width: 36, height: 36)
                            .background(picked ? AnyShapeStyle(tone.solid) : AnyShapeStyle(tone.fill), in: Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(symbol)
                }
            }
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
    }
}
