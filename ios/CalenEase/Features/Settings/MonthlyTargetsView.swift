import SwiftUI

/// 每月基本工时。默认按「周一至周五 × 日标准工时 − 落在工作日的法定节假日」推算，
/// 每年的调休与补班另行公布、不是固定规则，所以推算值明确标出来，并允许逐月修正。
struct MonthlyTargetsView: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast

    @State private var year: Int
    @State private var editing: ReportingMonth?

    init() {
        let parts = ScheduleCalendar.calendar.dateComponents([.year], from: Date())
        _year = State(initialValue: parts.year ?? 2026)
    }

    private var document: ScheduleDocument { store.document }

    var body: some View {
        Form {
            Section {
                Stepper("年份 \(String(year))", value: $year, in: 2025...2050)
            }
            Section {
                ForEach(0..<12, id: \.self) { month in
                    let key = ScheduleCalendar.monthKey(year: year, month: month)
                    let override = document.targets[key]
                    let value = WorkHours.monthlyTarget(document, year: year, month: month,
                                                        holidays: store.holidays)
                    Button {
                        editing = ReportingMonth(year: year, month: month)
                    } label: {
                        HStack {
                            Text("\(month + 1)月").foregroundStyle(.primary)
                            Spacer()
                            Text(HoursFormatter.hours(value))
                                .monospacedDigit()
                                .foregroundStyle(override == nil ? Color.secondary : Palette.blue)
                            Text(override == nil ? "推算" : "已修正")
                                .font(.caption2)
                                .foregroundStyle(override == nil ? Color.secondary.opacity(0.7) : Palette.blue)
                                .frame(width: 40, alignment: .trailing)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("\(String(year))年每月基本工时")
            } footer: {
                Text("推算值不含当年调休与补班安排；如果公司按官方公布的月计薪天数执行，可以在这里手动改。")
            }
        }
        .pageBackground()
        .navigationTitle("每月基本工时")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { month in
            MonthlyTargetEditor(month: month)
        }
    }
}

private struct MonthlyTargetEditor: View {
    let month: ReportingMonth

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    @Environment(\.dismiss) private var dismiss

    @State private var hours: Double = 0
    @State private var loaded = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledStepper(label: "基本工时", value: $hours, step: 1, range: 0...400)
                } header: {
                    Text(month.fullLabel)
                } footer: {
                    Text("推算值为 \(HoursFormatter.hours(estimate))。")
                }
                Section {
                    Button("恢复为推算值") {
                        store.setMonthlyTarget(nil, year: month.year, month: month.month)
                        showToast("已恢复推算值")
                        dismiss()
                    }
                }
            }
            .pageBackground()
            .navigationTitle("修正基本工时")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        store.setMonthlyTarget(hours, year: month.year, month: month.month)
                        showToast("已保存 \(month.fullLabel)")
                        dismiss()
                    }
                }
            }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                hours = WorkHours.monthlyTarget(store.document, month: month)
            }
        }
    }

    private var estimate: Double {
        WorkHours.estimateMonthlyTarget(year: month.year,
                                        month: month.month,
                                        dailyStandard: store.document.work.system == .comprehensive
                                            ? 8 : store.document.work.dailyStandard)
    }
}
