import SwiftUI

/// 班次编辑。传 nil 表示新建。
struct ShiftEditorView: View {
    let shift: ShiftDefinition?

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var draft = ShiftDefinition(id: "", name: "", shortName: "", color: AccentHex.blue)
    @State private var startTime = Date()
    @State private var endTime = Date()
    @State private var hasTimeRange = true
    @State private var loaded = false
    @State private var showsDeleteConfirm = false

    private var isNew: Bool { shift == nil }
    /// 内置的休息班次是循环和统计的基准，不允许删。
    private var isProtected: Bool { draft.id == ShiftID.rest }

    var body: some View {
        NavigationStack {
            Form {
                Section("名称") {
                    TextField("班次名称", text: $draft.name)
                    TextField("简称（日历上显示）", text: $draft.shortName)
                        .onChange(of: draft.shortName) { _, value in
                            if value.count > 4 { draft.shortName = String(value.prefix(4)) }
                        }
                }

                Section("颜色") {
                    ColorPaletteRow(palette: AccentHex.shiftPalette, selection: $draft.color)
                }

                Section {
                    Toggle("这是休息类班次", isOn: $draft.isRest)
                        .onChange(of: draft.isRest) { _, isRest in
                            if isRest {
                                draft.countsAsWork = false
                                draft.defaultHours = 0
                                hasTimeRange = false
                            } else {
                                draft.countsAsWork = true
                            }
                        }
                    if !draft.isRest {
                        Toggle("计入工作日与工时", isOn: $draft.countsAsWork)
                        Toggle("有固定时间段", isOn: $hasTimeRange)
                        if hasTimeRange {
                            DatePicker("开始", selection: $startTime, displayedComponents: .hourAndMinute)
                            DatePicker("结束", selection: $endTime, displayedComponents: .hourAndMinute)
                            Toggle("跨越零点", isOn: $draft.crossesMidnight)
                            HStack {
                                Text("按时间段计算时长")
                                Spacer()
                                Text(HoursFormatter.hours(computedDuration))
                                    .foregroundStyle(.secondary)
                                Button("采用") { draft.defaultHours = computedDuration }
                                    .buttonStyle(.borderless)
                                    .font(.caption.weight(.semibold))
                            }
                        }
                        LabeledStepper(label: "默认工时", value: $draft.defaultHours, step: 0.5, range: 0...24)
                    }
                } header: {
                    Text("时间与工时")
                } footer: {
                    Text("默认工时用于新排的班；单日可以随时改成实际工时。")
                }

                if !isNew, !isProtected {
                    Section {
                        Button(role: .destructive) {
                            showsDeleteConfirm = true
                        } label: {
                            Label("删除这个班次", systemImage: "trash")
                                .foregroundStyle(.red)
                        }
                    } footer: {
                        Text(usageFooter)
                    }
                }
            }
            .pageBackground()
            .navigationTitle(isNew ? "新增班次" : "编辑班次")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .confirmationDialog("删除后，已排这个班的日子会一并清空。",
                                isPresented: $showsDeleteConfirm, titleVisibility: .visible) {
                Button("删除班次", role: .destructive) {
                    if let shift { store.deleteShift(shift) }
                    showToast("班次已删除", symbol: "trash")
                    dismiss()
                }
                Button("取消", role: .cancel) {}
            }
            .onAppear(perform: load)
        }
    }

    private var computedDuration: Double {
        ShiftDefinition.duration(startTime: clock(startTime),
                                 endTime: clock(endTime),
                                 crossesMidnight: draft.crossesMidnight)
    }

    private var usageFooter: String {
        let count = shift.map { store.usageCount(of: $0) } ?? 0
        return count > 0 ? "当前有 \(count) 天排了这个班，删除会一并清空这些天。" : "还没有任何一天排这个班。"
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if let shift {
            draft = shift
            hasTimeRange = !shift.startTime.isEmpty && !shift.endTime.isEmpty
        } else {
            let used = Set(store.document.shifts.map(\.color))
            draft = ShiftDefinition(id: ShiftCatalog.makeId("shift"),
                                    name: "",
                                    shortName: "",
                                    color: AccentHex.shiftPalette.first { !used.contains($0) } ?? AccentHex.blue,
                                    startTime: "09:00",
                                    endTime: "18:00",
                                    defaultHours: 8)
        }
        startTime = time(from: draft.startTime) ?? defaultTime(hour: 9)
        endTime = time(from: draft.endTime) ?? defaultTime(hour: 18)
    }

    private func save() {
        var next = draft
        next.name = next.name.trimmingCharacters(in: .whitespaces)
        if next.shortName.trimmingCharacters(in: .whitespaces).isEmpty {
            next.shortName = String(next.name.prefix(2))
        }
        if next.isRest || !hasTimeRange {
            next.startTime = ""
            next.endTime = ""
            next.crossesMidnight = false
        } else {
            next.startTime = clock(startTime)
            next.endTime = clock(endTime)
        }
        if next.isRest {
            next.defaultHours = 0
            next.countsAsWork = false
        }
        store.saveShift(next)
        showToast(isNew ? "已新增班次" : "已保存")
        dismiss()
    }

    private func clock(_ date: Date) -> String {
        let parts = ScheduleCalendar.calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    private func time(from clock: String) -> Date? {
        let pieces = clock.split(separator: ":")
        guard pieces.count == 2, let hour = Int(pieces[0]), let minute = Int(pieces[1]) else { return nil }
        return ScheduleCalendar.calendar.date(bySettingHour: hour, minute: minute, second: 0, of: Date())
    }

    private func defaultTime(hour: Int) -> Date {
        ScheduleCalendar.calendar.date(bySettingHour: hour, minute: 0, second: 0, of: Date()) ?? Date()
    }
}

/// 强调色选择条，班次和标签共用。
struct ColorPaletteRow: View {
    let palette: [String]
    @Binding var selection: String

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 12)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(palette, id: \.self) { hex in
                let color = Color(hexString: hex)
                Button {
                    selection = hex
                } label: {
                    Circle()
                        .fill(color)
                        .frame(height: 34)
                        .overlay {
                            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 0.8)
                        }
                        .overlay {
                            if selection.lowercased() == hex.lowercased() {
                                Image(systemName: "checkmark")
                                    .font(.footnote.weight(.bold))
                                    .foregroundStyle(.white)
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }
}
