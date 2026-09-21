import Charts
import SwiftUI

/// 统计页。按功能开关切换成三种形态：仅排班、仅工时、工时与加班。
struct StatsScreen: View {
    @Environment(ScheduleStore.self) private var store
    @State private var scope: StatsScope = .month

    private var document: ScheduleDocument { store.document }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    scopePicker
                    summarySection
                    if document.work.trackHours {
                        progressSection
                        hoursChartSection
                    }
                    compositionSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background(Palette.canvas)
            .navigationTitle("统计")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - 范围

    enum StatsScope: String, CaseIterable, Identifiable {
        case month, year
        var id: String { rawValue }
        var label: String { self == .month ? "本月" : "年度周期" }
    }

    private var cycle: AnnualCycle {
        WorkHours.reportingCycle(for: document, year: store.focusedYear, month: store.focusedMonth)
    }

    private var scopeMonths: [ReportingMonth] {
        scope == .month
            ? [ReportingMonth(year: store.focusedYear, month: store.focusedMonth)]
            : cycle.months
    }

    private var scopeLabel: String {
        scope == .month ? store.focusedMonthLabel : cycle.label
    }

    private var scopeRecords: [DayRecord] { document.records(inMonths: scopeMonths) }
    private var workRecords: [DayRecord] { WorkHours.workRecords(document, in: scopeRecords) }
    private var completedRecords: [DayRecord] {
        workRecords.filter { $0.countsAsCompleted(today: store.todayKey) }
    }

    private var plannedHours: Double { workRecords.reduce(0) { $0 + $1.hours } }
    private var actualHours: Double { completedRecords.reduce(0) { $0 + $1.hours } }
    private var basicHours: Double { WorkHours.target(document, months: scopeMonths) }
    private var overtime: Double {
        WorkHours.periodOvertime(document, records: workRecords, months: scopeMonths)
    }

    private var scopePicker: some View {
        Picker("统计范围", selection: $scope.animation(.spring(response: 0.3, dampingFraction: 1))) {
            ForEach(StatsScope.allCases) { item in
                Text(item.label).tag(item)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - 概览

    private var summarySection: some View {
        let restDays = scopeRecords.filter { document.shift($0.shiftId)?.isRest == true }.count
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: document.work.trackHours ? "工时概览" : "出勤概览",
                          eyebrow: scopeLabel,
                          badge: "\(workRecords.count) 个班")
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                MetricTile(label: "出勤天数", value: "\(workRecords.count)天",
                           detail: "休息 \(restDays) 天", tint: Palette.blue, symbol: "calendar")
                MetricTile(label: "已完成", value: "\(completedRecords.count)天",
                           detail: "剩余 \(max(0, workRecords.count - completedRecords.count)) 天",
                           tint: Palette.green, symbol: "checkmark.circle")
                if document.work.trackHours {
                    MetricTile(label: "计划工时", value: HoursFormatter.hours(plannedHours),
                               detail: "已完成 \(HoursFormatter.hours(actualHours))",
                               tint: Palette.purple, symbol: "clock")
                    MetricTile(label: "基本工时", value: HoursFormatter.hours(basicHours),
                               detail: basicDetail, tint: Palette.cyan, symbol: "target")
                }
                if document.work.trackHours && document.work.trackOvertime {
                    MetricTile(label: "额外工时", value: HoursFormatter.hours(overtime),
                               detail: "\(document.work.system.label) · \(document.work.compensation.label)",
                               tint: Palette.orange, symbol: "bolt")
                }
            }
        }
        .card()
    }

    private var basicDetail: String {
        let diff = plannedHours - basicHours
        if diff > 0 { return "计划高出 \(HoursFormatter.hours(diff))" }
        if diff < 0 { return "计划少 \(HoursFormatter.hours(-diff))" }
        return "与基本工时持平"
    }

    // MARK: - 进度

    private var progressSection: some View {
        let ratio = basicHours > 0 ? actualHours / basicHours : 0
        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "已完成 / 基本工时", eyebrow: "进度")
            HStack(spacing: 18) {
                ProgressRing(progress: ratio,
                             caption: HoursFormatter.compact(actualHours),
                             subcaption: "／\(HoursFormatter.compact(basicHours))h")
                VStack(alignment: .leading, spacing: 9) {
                    LegendRow(color: Palette.green, label: "已完成", value: HoursFormatter.hours(actualHours))
                    LegendRow(color: Palette.purple, label: "计划中", value: HoursFormatter.hours(plannedHours))
                    LegendRow(color: Palette.cyan, label: "基本工时", value: HoursFormatter.hours(basicHours))
                    if document.work.trackOvertime {
                        LegendRow(color: Palette.orange, label: "额外工时", value: HoursFormatter.hours(overtime))
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    // MARK: - 工时曲线

    private struct MonthlyPoint: Identifiable {
        let id: String
        let label: String
        let basic: Double
        let planned: Double
        /// 超出基本工时的部分，没超出时等于基本工时（面积就为零）。
        var overtimeTop: Double { max(planned, basic) }
        var overtime: Double { max(0, planned - basic) }
    }

    private var monthlyPoints: [MonthlyPoint] {
        cycle.months.map { month in
            let records = WorkHours.workRecords(document, in: document.records(inMonth: month))
            return MonthlyPoint(id: month.key,
                                label: month.label,
                                basic: WorkHours.monthlyTarget(document, month: month),
                                planned: records.reduce(0) { $0 + $1.hours })
        }
    }

    /// 排了班的月份。没排班的月份不画计划线，否则会和基本工时线重合，
    /// 看着像「计划工时正好等于基本工时」。
    private var scheduledPoints: [MonthlyPoint] { monthlyPoints.filter { $0.planned > 0 } }

    /// 基本工时打底，加班量堆在它上面：两条线之间的面积就是这个年度里
    /// 每个月超出的部分，比并排的柱子更容易看出「哪几个月在往上顶」。
    private var hoursChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "每月工时走势", eyebrow: cycle.label,
                          badge: document.work.trackOvertime ? "含额外工时" : nil)

            Chart {
                ForEach(monthlyPoints) { point in
                    AreaMark(x: .value("月份", point.label),
                             y: .value("基本工时", point.basic),
                             series: .value("类型", "基本"))
                        .foregroundStyle(
                            LinearGradient(colors: [Palette.cyan.opacity(0.35), Palette.cyan.opacity(0.04)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.monotone)
                }

                if document.work.trackOvertime {
                    // 只填基本工时线以上的那一段
                    ForEach(scheduledPoints) { point in
                        AreaMark(x: .value("月份", point.label),
                                 yStart: .value("基本工时", point.basic),
                                 yEnd: .value("计划工时", point.overtimeTop))
                            .foregroundStyle(
                                LinearGradient(colors: [Palette.orange.opacity(0.42), Palette.orange.opacity(0.06)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .interpolationMethod(.monotone)
                    }
                }

                ForEach(monthlyPoints) { point in
                    LineMark(x: .value("月份", point.label),
                             y: .value("基本工时", point.basic),
                             series: .value("类型", "基本"))
                        .foregroundStyle(Palette.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                        .interpolationMethod(.monotone)
                }

                if document.work.trackOvertime {
                    ForEach(scheduledPoints) { point in
                        LineMark(x: .value("月份", point.label),
                                 y: .value("计划工时", point.overtimeTop),
                                 series: .value("类型", "计划"))
                            .foregroundStyle(Palette.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { value in
                    AxisGridLine().foregroundStyle(Palette.hairline.opacity(0.4))
                    AxisValueLabel {
                        if let hours = value.as(Double.self) {
                            Text(HoursFormatter.compact(hours)).font(.caption2)
                        }
                    }
                }
            }
            .chartXAxis {
                AxisMarks { value in
                    AxisValueLabel {
                        if let label = value.as(String.self) {
                            Text(label).font(.caption2)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 190)

            HStack(spacing: 14) {
                LegendRow(color: Palette.cyan, label: "基本工时", value: "")
                if document.work.trackOvertime {
                    LegendRow(color: Palette.orange, label: "计划工时（超出部分即加班）", value: "")
                }
                Spacer(minLength: 0)
            }
        }
        .card()
    }

    // MARK: - 班次构成

    private var composition: [(shift: ShiftDefinition, count: Int)] {
        var counts: [String: Int] = [:]
        for record in scopeRecords { counts[record.shiftId, default: 0] += 1 }
        return counts.compactMap { id, count in document.shift(id).map { ($0, count) } }
            .sorted { $0.count > $1.count }
    }

    private var compositionSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "班次构成", eyebrow: scopeLabel, badge: "\(scopeRecords.count) 天")
            if composition.isEmpty {
                Text("这段时间还没有排班记录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                let total = max(1, scopeRecords.count)
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(composition, id: \.shift.id) { item in
                            Capsule()
                                .fill(item.shift.tint)
                                .frame(width: max(4, proxy.size.width * CGFloat(item.count) / CGFloat(total)))
                        }
                    }
                }
                .frame(height: 10)

                VStack(spacing: 10) {
                    ForEach(composition, id: \.shift.id) { item in
                        HStack(spacing: 10) {
                            ShiftOrb(shift: item.shift, size: 26)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.shift.name).font(.subheadline)
                                if !item.shift.fullRange.isEmpty {
                                    Text(item.shift.fullRange)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            Spacer(minLength: 0)
                            Text("\(item.count) 天")
                                .font(.subheadline.weight(.semibold))
                                .monospacedDigit()
                            Text("\(Int((Double(item.count) / Double(total) * 100).rounded()))%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 42, alignment: .trailing)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
        .card()
    }
}

/// 圆环进度。超出基本工时的部分再叠一圈橙色。
struct ProgressRing: View {
    let progress: Double
    let caption: String
    let subcaption: String

    var body: some View {
        ZStack {
            Circle().stroke(Palette.inset, lineWidth: 12)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Palette.green, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if progress > 1 {
                Circle()
                    .trim(from: 0, to: min(progress - 1, 1))
                    .stroke(Palette.orange, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(9)
            }
            VStack(spacing: 1) {
                Text(caption)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(subcaption).font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            }
        }
        .frame(width: 112, height: 112)
        .animation(.spring(response: 0.5, dampingFraction: 1), value: progress)
    }
}

struct LegendRow: View {
    let color: Color
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).font(.caption).foregroundStyle(.secondary)
            if !value.isEmpty {
                Text(value).font(.caption.weight(.semibold)).monospacedDigit()
            }
        }
    }
}
