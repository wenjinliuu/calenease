import SwiftUI

/// 循环排班。可以直接套用模板，也可以按班次一个个拼出自己的序列。
/// 保存的是班次 ID 序列，所以自定义班次同样能用，并且会跨年度持续生成。
struct CycleGeneratorSheet: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var name = "我的循环"
    @State private var startDate = Date()
    @State private var shiftIds: [String] = []
    @State private var saveAsTemplate = false

    private var document: ScheduleDocument { store.document }

    /// 一轮最多 62 天，和 web 版一致。
    private let maxLength = 62

    var body: some View {
        NavigationStack {
            Form {
                if let active = document.activeCycle {
                    Section("当前循环") {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(active.name).font(.subheadline.weight(.semibold))
                            Text("\(active.startDate) 起 · \(active.shiftIds.count) 天一轮")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            CycleStrip(shiftIds: active.shiftIds, document: document)
                        }
                        Button(role: .destructive) {
                            store.stopCycle()
                            showToast("已停用循环，已生成的排班保持不变", symbol: "pause.circle")
                            dismiss()
                        } label: {
                            Label("停用循环", systemImage: "pause.circle")
                                .foregroundStyle(.red)
                        }
                    }
                }

                Section("从模板开始") {
                    ForEach(templates) { template in
                        Button {
                            shiftIds = template.shiftIds
                            name = template.name
                        } label: {
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(template.name).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text(template.lengthLabel)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                if !template.caption.isEmpty {
                                    Text(template.caption)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                CycleStrip(shiftIds: template.shiftIds, document: document)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    if shiftIds.isEmpty {
                        Text("点下面的班次，一天一天拼出你的循环。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        CycleStrip(shiftIds: shiftIds, document: document, showsIndex: true)
                        HStack {
                            Button("删掉最后一天") { _ = shiftIds.popLast() }
                                .buttonStyle(SecondaryButton(tint: Palette.orange))
                            Spacer()
                            Button("清空") { shiftIds = [] }
                                .buttonStyle(SecondaryButton(tint: Palette.red))
                        }
                    }
                    ShiftPickerGrid(shifts: document.orderedShifts, selection: "") { shift in
                        guard shiftIds.count < maxLength else { return }
                        shiftIds.append(shift.id)
                    }
                } header: {
                    Text("循环序列 · \(shiftIds.count) 天")
                } footer: {
                    Text("班次按顺序不断重复，一轮最多 \(maxLength) 天。")
                }

                Section("生效设置") {
                    TextField("循环名称", text: $name)
                    DatePicker("生效日（第 1 天）", selection: $startDate, displayedComponents: .date)
                        .environment(\.locale, Locale(identifier: "zh_CN"))
                    Toggle(isOn: $saveAsTemplate) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("保存为「我的循环」")
                            Text("以后可以一键再次使用").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Label("\(startKey) 之前的记录不变；当天及之后按新循环生成，浏览以后的年份会自动延续。",
                          systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .pageBackground()
            .navigationTitle("循环排班")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("从生效日开始") { apply() }
                        .disabled(shiftIds.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: prefillFromActiveCycle)
        }
    }

    private var templates: [CycleTemplate] {
        let available = Set(document.shifts.map(\.id))
        return document.cycleTemplates.filter { $0.shiftIds.allSatisfy(available.contains) }
    }

    private var startKey: String { ScheduleCalendar.key(startDate) }

    /// 已经在用某套循环时，进来就填好它，改起点或改某一天都不用从头拼。
    private func prefillFromActiveCycle() {
        guard shiftIds.isEmpty, let active = document.activeCycle else { return }
        shiftIds = active.shiftIds
        name = active.name
        if let date = ScheduleCalendar.date(from: active.startDate) { startDate = date }
    }

    private func apply() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if saveAsTemplate {
            store.update { document in
                document.cycleTemplates.append(CycleTemplate(id: ShiftCatalog.makeId("tpl"),
                                                             name: trimmed,
                                                             caption: "自定义循环",
                                                             shiftIds: shiftIds,
                                                             category: .custom))
            }
        }
        store.applyCycle(name: trimmed, startDate: startKey, shiftIds: shiftIds)
        showToast("已按新循环生成排班", symbol: "sparkles")
        dismiss()
    }
}

/// 循环序列的可视化色带。
struct CycleStrip: View {
    let shiftIds: [String]
    let document: ScheduleDocument
    var showsIndex = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(Array(shiftIds.enumerated()), id: \.offset) { index, id in
                    let shift = document.shift(id)
                    VStack(spacing: 2) {
                        Text(shift?.shortName ?? "?")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(shift?.inkOnTint ?? .white)
                            .frame(width: 26, height: 26)
                            .background(shift.map { AnyShapeStyle($0.tint) } ?? AnyShapeStyle(Color.gray),
                                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        if showsIndex {
                            Text("\(index + 1)")
                                .font(.system(size: 8))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }
}
