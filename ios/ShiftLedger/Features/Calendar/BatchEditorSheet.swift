import SwiftUI

/// 区间批量修改：把选中的整段日期统一改成同一个班次。
struct BatchEditorSheet: View {
    let dates: [String]

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var shiftId = ""
    @State private var hours: Double = 0
    @State private var tagIds: [String] = []
    @State private var overwritesTags = false

    private var document: ScheduleDocument { store.document }

    var body: some View {
        NavigationStack {
            Form {
                Section("统一设置为") {
                    ShiftPickerGrid(shifts: document.orderedShifts, selection: shiftId) { shift in
                        shiftId = shift.id
                        hours = shift.defaultHours
                    }
                }

                if document.work.trackHours, document.shift(shiftId)?.countsAsWork == true {
                    Section("工时") {
                        LabeledStepper(label: "统一工时", value: $hours, step: 0.5, range: 0...24)
                    }
                }

                if !document.tags.isEmpty {
                    Section {
                        Toggle("同时覆盖职责标签", isOn: $overwritesTags)
                        if overwritesTags {
                            TagPickerFlow(tags: document.tags, selection: $tagIds)
                        }
                    } header: {
                        Text("职责标签")
                    } footer: {
                        Text("不开启就只改班次和工时，原有标签保持不变。")
                    }
                }

                Section {
                    Label("只覆盖 \(dates.first ?? "") 至 \(dates.last ?? "")，其他日期和未来循环不变。",
                          systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .pageBackground()
            .navigationTitle("批量修改 · \(dates.count) 天")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("返回") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("确认修改") {
                        store.applyBatch(dates: dates,
                                         shiftId: shiftId,
                                         hours: document.work.trackHours ? hours : nil,
                                         tagIds: overwritesTags ? tagIds : nil)
                        showToast("已修改 \(dates.count) 天")
                        dismiss()
                    }
                    .disabled(shiftId.isEmpty)
                }
            }
            .onAppear {
                guard shiftId.isEmpty, let first = document.orderedShifts.first else { return }
                shiftId = first.id
                hours = first.defaultHours
            }
        }
    }
}
