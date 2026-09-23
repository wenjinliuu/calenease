import Charts
import SwiftUI

/// 统计页。按功能开关切换成三种形态：仅排班、仅工时、工时与加班。
///
/// 顶上先分「月度 / 年度」，下面一条和日历页同款的切换条：左右箭头逐月或逐年度翻，
/// 点中间的标题弹出年月选择器。查看的月份和日历页是同一个，两边切了互相跟着走。
struct StatsScreen: View {
    @Environment(ScheduleStore.self) private var store
    @State private var scope: StatsScope = .month
    @State private var isPeriodPickerPresented = false
    /// 走势图上长按选中的月份（横轴标签）。
    @State private var selectedMonthLabel: String?

    private var document: ScheduleDocument { store.document }

    var body: some View {
        // 基本工时按 `HolidayCalendar.shared` 推算；读一下 store.holidays，
        // 放假安排下载更新后这一页跟着重算。
        let _ = store.holidays
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    periodPanel
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
            .sheet(isPresented: $isPeriodPickerPresented) { periodPicker }
            .sensoryFeedback(.selection, trigger: store.focusedMonthKey)
        }
    }

    // MARK: - 范围

    enum StatsScope: String, CaseIterable, Identifiable {
        case month, year
        var id: String { rawValue }
        var label: String { self == .month ? "月度" : "年度" }
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

    /// 月度 / 年度 + 前后切换。
    private var periodPanel: some View {
        VStack(spacing: 12) {
            scopePicker
            MonthSwitcher(label: scopeLabel,
                          previousLabel: scope == .month ? "上个月" : "上个年度",
                          nextLabel: scope == .month ? "下个月" : "下个年度",
                          todayTitle: scope == .month ? "本月" : "本年度",
                          onPrevious: { step(-1) },
                          onNext: { step(1) },
                          onToday: {
                              withAnimation(.smooth(duration: 0.3)) { store.goToCurrentMonth() }
                          },
                          onPickLabel: { isPeriodPickerPresented = true })
        }
        .card(cornerRadius: 22, padding: 12)
    }

    /// 按月时前后一个月，按年度时前后一整个年度（12 个月）。
    private func step(_ direction: Int) {
        withAnimation(.smooth(duration: 0.3)) {
            store.changeMonth(by: direction * (scope == .month ? 1 : 12))
        }
    }

    private var periodPicker: some View {
        let current = store.currentMonthIndex
        let annualStart = cycle.startMonth + 1
        let currentCycle = WorkHours.reportingCycle(for: document, year: current / 12, month: current % 12)
        return PeriodPickerSheet(mode: scope == .month ? .month : .year,
                                 selectedYear: scope == .month ? store.focusedYear : cycle.startYear,
                                 selectedMonth: store.focusedMonth,
                                 currentYear: scope == .month ? current / 12 : currentCycle.startYear,
                                 currentMonth: current % 12,
                                 annualStartMonth: annualStart) { year, month in
            withAnimation(.smooth(duration: 0.3)) { store.focus(year: year, month: month) }
        }
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
                           detail: "休息 \(restDays) 天", tint: Palette.green, symbol: "calendar")
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
        /// 计划减基本。正的是额外工时，负的是这个月比基本工时少排的部分。
        var extra: Double { planned - basic }
        /// 两条线之间的面积：高出的部分和不足的部分分开上色。
        var surplusTop: Double { max(planned, basic) }
        var shortfallBottom: Double { min(planned, basic) }
    }

    private var selectedPoint: MonthlyPoint? {
        selectedMonthLabel.flatMap { label in monthlyPoints.first { $0.label == label } }
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
                    // 两条线之间：高出基本工时的月份填橙色，排得比基本工时少的月份填红色，
                    // 计划线会真的穿到基本工时线下面去。
                    ForEach(scheduledPoints) { point in
                        AreaMark(x: .value("月份", point.label),
                                 yStart: .value("基本工时", point.basic),
                                 yEnd: .value("高出", point.surplusTop),
                                 series: .value("类型", "高出"))
                            .foregroundStyle(Palette.orange.opacity(0.28))
                            .interpolationMethod(.monotone)
                        AreaMark(x: .value("月份", point.label),
                                 yStart: .value("不足", point.shortfallBottom),
                                 yEnd: .value("基本工时", point.basic),
                                 series: .value("类型", "不足"))
                            .foregroundStyle(Palette.red.opacity(0.18))
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
                                 y: .value("计划工时", point.planned),
                                 series: .value("类型", "计划"))
                            .foregroundStyle(Palette.orange)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.monotone)
                    }
                }

                // 长按选中某个月：一条竖线，顶上一张小卡写这个月的计划、基本、额外。
                if let selected = selectedPoint {
                    RuleMark(x: .value("月份", selected.label))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top,
                                    spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            MonthCallout(label: selected.label,
                                         planned: selected.planned,
                                         basic: selected.basic,
                                         showsExtra: document.work.trackOvertime)
                        }
                }
            }
            // 长按 0.3 秒选中，按住左右拖换月份，松手收起。用 UIKit 的长按识别器而不是
            // `chartXSelection`：后者一碰就开始选，放在滚动页里会和上下滑动抢手势。
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(ChartLongPress { location in
                            guard let location, let plotFrame = proxy.plotFrame else {
                                selectedMonthLabel = nil
                                return
                            }
                            let x = location.x - geometry[plotFrame].origin.x
                            if let label: String = proxy.value(atX: x) { selectedMonthLabel = label }
                        })
                }
            }
            .sensoryFeedback(.selection, trigger: selectedMonthLabel)
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
                    LegendRow(color: Palette.orange, label: "计划工时", value: "")
                }
                Spacer(minLength: 0)
            }
            Text("长按图表查看当月明细")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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

/// 图表上的长按：按住 0.3 秒后开始回报手指位置，按住拖动持续回报，松手回报 nil。
/// 长按识别之前手指一动就失败，页面照常上下滚动。
private struct ChartLongPress: UIGestureRecognizerRepresentable {
    let onChange: (CGPoint?) -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.3
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began, .changed:
            onChange(context.converter.localLocation)
        default:
            onChange(nil)
        }
    }
}

/// 走势图长按时浮在选中月份上方的小卡。
private struct MonthCallout: View {
    let label: String
    let planned: Double
    let basic: Double
    let showsExtra: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption.weight(.semibold))
            row("计划", planned, color: Palette.orange)
            row("基本", basic, color: Palette.cyan)
            if showsExtra {
                let extra = planned - basic
                row(extra < 0 ? "不足" : "额外", abs(extra), color: extra < 0 ? Palette.red : Palette.orange,
                    sign: extra < 0 ? "−" : "+")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Palette.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Palette.cardStroke, lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.08), radius: 6, y: 2)
    }

    private func row(_ title: String, _ value: Double, color: Color, sign: String = "") -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(sign + HoursFormatter.hours(value))
                .font(.caption2.weight(.semibold))
                .monospacedDigit()
        }
        .frame(minWidth: 108)
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
