import SwiftUI

/// 逐日编辑。改的只是当天，不会打断后续循环——要改未来请用"循环排班"。
struct DayEditorSheet: View {
    let date: String

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var draft = DayRecord(date: "", shiftId: "", hours: 0)
    @State private var loaded = false

    private var document: ScheduleDocument { store.document }
    private var selectedShift: ShiftDefinition? { document.shift(draft.shiftId) }

    var body: some View {
        NavigationStack {
            Form {
                Section("主要班次") {
                    ShiftPickerGrid(shifts: document.orderedShifts,
                                    selection: draft.shiftId) { shift in
                        draft.shiftId = shift.id
                        draft.hours = shift.defaultHours
                    }
                }

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

                Section("备注") {
                    TextField("这一天需要记点什么？", text: Binding(get: { draft.note ?? "" },
                                                        set: { draft.note = $0.isEmpty ? nil : $0 }),
                              axis: .vertical)
                        .lineLimit(1...4)
                }

                Section {
                    Label("这里只修改当天，不会改变后续循环。要改变未来，请使用「循环排班」。",
                          systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button(role: .destructive) {
                        store.clearDay(date)
                        showToast("已清空当天", symbol: "trash")
                        dismiss()
                    } label: {
                        Label("清空这一天", systemImage: "trash")
                            .foregroundStyle(.red)
                    }
                }
            }
            .pageBackground()
            .navigationTitle(titleText)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        var record = draft
                        record.planned = true
                        store.save(record)
                        showToast("已保存 \(date)")
                        dismiss()
                    }
                    .disabled(draft.shiftId.isEmpty)
                }
            }
            .onAppear(perform: loadDraft)
        }
    }

    /// 标题写「9月9日 周三」，是法定节假日再缀上名字。
    private var titleText: String {
        guard let parts = ScheduleCalendar.components(from: date) else { return date }
        let weekday = ScheduleCalendar.weekdaySymbols[ScheduleCalendar.weekdayIndex(date)]
        var text = "\(parts.month + 1)月\(parts.day)日 周\(weekday)"
        let holiday = Holidays.name(of: date)
        if !holiday.isEmpty { text += " · \(holiday)" }
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
        loaded = true
        if let existing = store.record(on: date) {
            draft = existing
        } else {
            let fallback = document.orderedShifts.first
            draft = DayRecord(date: date,
                              shiftId: fallback?.id ?? "",
                              hours: fallback?.defaultHours ?? 0,
                              source: .manual)
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
