import SwiftUI

/// 逐日编辑。改的只是当天，不会打断后续循环——要改未来请用"循环排班"。
struct DayEditorSheet: View {
    let date: String

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var draft = DayRecord(date: "", shiftId: "", hours: 0)
    @State private var loaded = false
    /// 次要班次那一块展开了没有。默认收着，只露一个「添加次要班次」。
    @State private var showsSecondary = false
    /// 表单内容实际要多高。抽屉按它定高度，正好露到「清空这一天」为止。
    @State private var contentHeight: CGFloat?

    private var document: ScheduleDocument { store.document }
    private var selectedShift: ShiftDefinition? { document.shift(draft.shiftId) }

    var body: some View {
        NavigationStack {
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
            // 量表单内容的总高度（含导航栏和底部安全区），抽屉就开这么高。
            // 内容比屏幕还高时系统会封顶到全屏，表单自己滚动。
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                (geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom).rounded(.up)
            } action: { _, height in
                guard height > 0 else { return }
                withAnimation(.smooth(duration: 0.3)) { contentHeight = height }
            }
        }
        // 抽屉高度跟着内容走：露到「清空这一天」为止，不多不少。
        // 展开次要班次时内容变高，抽屉跟着长高。
        .presentationDetents([contentHeight.map { PresentationDetent.height($0) } ?? .medium])
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(28)
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
        loaded = true
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
