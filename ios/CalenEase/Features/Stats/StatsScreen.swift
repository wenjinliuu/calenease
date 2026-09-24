import Charts
import SwiftUI

/// 工时页（原来叫统计）。按功能开关切换成三种形态：仅排班、仅工时、工时与加班。
///
/// 没有单独的切换条了：期间写在概览卡片的标题上，点它弹出年月选择器，
/// 左右箭头逐月或逐年度翻，旁边一个「月 / 年」按钮来回切。
/// 查看的月份和日历页是同一个，两边切了互相跟着走。
struct StatsScreen: View {
    @Environment(ScheduleStore.self) private var store
    @State private var scope: StatsScope = .month
    @State private var isPeriodPickerPresented = false

    private var document: ScheduleDocument { store.document }

    var body: some View {
        // 基本工时按 `HolidayCalendar.shared` 推算；读一下 store.holidays，
        // 放假安排下载更新后这一页跟着重算。
        let _ = store.holidays
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
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
            .navigationTitle("工时")
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

    /// 概览卡片顶上一行：期间（点开选年月）、前后翻、月 / 年切换。
    private var periodHeader: some View {
        HStack(alignment: .center, spacing: 8) {
            Button { isPeriodPickerPresented = true } label: {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(scopeLabel)
                        .font(.title3.weight(.bold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: Double(store.focusedIndex)))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "chevron.down")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                }
                .foregroundStyle(.primary)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("选择年月")

            Spacer(minLength: 4)

            circleButton("chevron.left", label: scope == .month ? "上个月" : "上个年度") { step(-1) }
            circleButton("chevron.right", label: scope == .month ? "下个月" : "下个年度") { step(1) }

            Button {
                withAnimation(.snappy(duration: 0.3)) { scope = scope == .month ? .year : .month }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "arrow.left.arrow.right")
                        .font(.system(size: 10, weight: .bold))
                    Text(scope == .month ? "月" : "年")
                        .font(.subheadline.weight(.bold))
                        .contentTransition(.interpolate)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(Palette.blue, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(scope == .month ? "按月查看，点按切到按年度" : "按年度查看，点按切到按月")
            .sensoryFeedback(.selection, trigger: scope)
        }
        .animation(.snappy(duration: 0.3), value: scopeLabel)
    }

    private func circleButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.primary)
                .frame(width: 32, height: 32)
                .background(Palette.inset, in: Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
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
            periodHeader
            SectionHeader(title: document.work.trackHours ? "工时概览" : "出勤概览",
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

    private var monthlyPoints: [HoursTrendChart.Point] {
        cycle.months.enumerated().map { index, month in
            let records = WorkHours.workRecords(document, in: document.records(inMonth: month))
            return HoursTrendChart.Point(index: index,
                                         label: month.label,
                                         basic: WorkHours.monthlyTarget(document, month: month),
                                         planned: records.reduce(0) { $0 + $1.hours })
        }
    }

    private var hoursChartSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "每月工时走势", eyebrow: cycle.label,
                          badge: document.work.trackOvertime ? "含额外工时" : nil)
            // 图表单独成一个视图，数据在这里算好一次交进去；长按时只重画图表自己，
            // 不再连累整页把每个月的工时重算一遍——之前长按拖动一卡一卡就是这个原因。
            HoursTrendChart(points: monthlyPoints, showsPlanned: document.work.trackOvertime)
                .equatable()
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
            row("计划", planned, color: Palette.purple)
            row("基本", basic, color: Palette.cyan)
            if showsExtra {
                let extra = planned - basic
                row(extra < 0 ? "不足" : "额外", abs(extra), color: extra < 0 ? Palette.red : Palette.orange,
                    sign: extra < 0 ? "−" : "+")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Palette.inset, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
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

/// 每月工时走势图。
///
/// 横轴用月份序号（数字）而不是月份文字：两条线交叉的地方要在两个月之间插一个交点，
/// 文字横轴插不进去。高出基本工时的部分填橙色，少于基本工时的部分填红色，
/// 两块面积都在交点处收成零——之前只按每个月的点填，交叉那一段会串色。
/// 线和面积都用折线连，不用平滑曲线：平滑曲线和交点对不上。
struct HoursTrendChart: View, Equatable {
    struct Point: Hashable, Identifiable {
        let index: Int
        let label: String
        let basic: Double
        let planned: Double
        var id: Int { index }
    }

    /// 面积用的点：x 可以落在两个月之间（交点）。`segment` 断开没排班的月份。
    struct AreaPoint: Hashable {
        let x: Double
        let basic: Double
        let planned: Double
        let segment: Int
    }

    let points: [Point]
    let showsPlanned: Bool

    @State private var selectedIndex: Int?

    nonisolated static func == (lhs: HoursTrendChart, rhs: HoursTrendChart) -> Bool {
        lhs.points == rhs.points && lhs.showsPlanned == rhs.showsPlanned
    }

    /// 排了班的月份。没排班的月份不画计划线，否则会和基本工时线重合。
    private var scheduled: [Point] { points.filter { $0.planned > 0 } }

    /// 相邻两个排了班的月份之间，如果计划线穿过基本线，就在交点处补一个点。
    static func areaPoints(_ scheduled: [Point]) -> [AreaPoint] {
        var result: [AreaPoint] = []
        var segment = 0
        for (offset, point) in scheduled.enumerated() {
            if offset > 0 {
                let previous = scheduled[offset - 1]
                if point.index - previous.index > 1 {
                    segment += 1
                } else {
                    let before = previous.planned - previous.basic
                    let after = point.planned - point.basic
                    if before * after < 0 {
                        let t = before / (before - after)
                        let basic = previous.basic + (point.basic - previous.basic) * t
                        result.append(AreaPoint(x: Double(previous.index) + t, basic: basic,
                                                planned: basic, segment: segment))
                    }
                }
            }
            result.append(AreaPoint(x: Double(point.index), basic: point.basic,
                                    planned: point.planned, segment: segment))
        }
        return result
    }

    var body: some View {
        let scheduled = scheduled
        let areas = Self.areaPoints(scheduled)
        let selected = selectedIndex.flatMap { index in points.first { $0.index == index } }
        let lastIndex = Double(max(points.count - 1, 0))

        VStack(alignment: .leading, spacing: 14) {
            Chart {
                ForEach(points) { point in
                    AreaMark(x: .value("月份", Double(point.index)),
                             y: .value("基本工时", point.basic),
                             series: .value("类型", "基本底"))
                        .foregroundStyle(
                            LinearGradient(colors: [Palette.cyan.opacity(0.3), Palette.cyan.opacity(0.03)],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .interpolationMethod(.linear)
                }

                if showsPlanned {
                    ForEach(Array(areas.enumerated()), id: \.offset) { _, point in
                        AreaMark(x: .value("月份", point.x),
                                 yStart: .value("基本工时", point.basic),
                                 yEnd: .value("高出", max(point.planned, point.basic)),
                                 series: .value("类型", "高出\(point.segment)"))
                            .foregroundStyle(Palette.orange.opacity(0.3))
                            .interpolationMethod(.linear)
                    }
                    ForEach(Array(areas.enumerated()), id: \.offset) { _, point in
                        AreaMark(x: .value("月份", point.x),
                                 yStart: .value("不足", min(point.planned, point.basic)),
                                 yEnd: .value("基本工时", point.basic),
                                 series: .value("类型", "不足\(point.segment)"))
                            .foregroundStyle(Palette.red.opacity(0.22))
                            .interpolationMethod(.linear)
                    }
                }

                ForEach(points) { point in
                    LineMark(x: .value("月份", Double(point.index)),
                             y: .value("基本工时", point.basic),
                             series: .value("类型", "基本"))
                        .foregroundStyle(Palette.cyan)
                        .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                        .interpolationMethod(.linear)
                }

                if showsPlanned {
                    ForEach(Array(areas.enumerated()), id: \.offset) { _, point in
                        LineMark(x: .value("月份", point.x),
                                 y: .value("计划工时", point.planned),
                                 series: .value("类型", "计划\(point.segment)"))
                            .foregroundStyle(Palette.purple)
                            .lineStyle(StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                            .interpolationMethod(.linear)
                    }
                    ForEach(scheduled) { point in
                        PointMark(x: .value("月份", Double(point.index)),
                                  y: .value("计划工时", point.planned))
                            .foregroundStyle(Palette.purple)
                            .symbolSize(point.index == selectedIndex ? 60 : 18)
                    }
                }

                // 长按选中某个月：一条竖线，顶上一张小卡写这个月的计划、基本、额外。
                if let selected {
                    RuleMark(x: .value("月份", Double(selected.index)))
                        .foregroundStyle(Color.secondary.opacity(0.5))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                        .annotation(position: .top,
                                    spacing: 4,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            MonthCallout(label: selected.label,
                                         planned: selected.planned,
                                         basic: selected.basic,
                                         showsExtra: showsPlanned)
                        }
                }
            }
            .chartXScale(domain: 0...max(lastIndex, 1))
            // 长按 0.3 秒选中，按住左右拖换月份，松手收起。只在换到另一个月时才更新状态，
            // 手指在同一个月里挪动不触发重画。
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle()
                        .fill(.clear)
                        .contentShape(Rectangle())
                        .gesture(ChartLongPress { location in
                            guard let location, let plotFrame = proxy.plotFrame else {
                                if selectedIndex != nil { selectedIndex = nil }
                                return
                            }
                            let x = location.x - geometry[plotFrame].origin.x
                            guard let value: Double = proxy.value(atX: x) else { return }
                            let index = Int(value.rounded())
                            let clamped = min(max(index, 0), points.count - 1)
                            if clamped != selectedIndex { selectedIndex = clamped }
                        })
                }
            }
            .sensoryFeedback(.selection, trigger: selectedIndex)
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
                AxisMarks(values: points.map { Double($0.index) }) { value in
                    AxisValueLabel {
                        if let raw = value.as(Double.self),
                           let point = points.first(where: { $0.index == Int(raw.rounded()) }) {
                            Text(point.label).font(.caption2)
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(height: 190)

            HStack(spacing: 14) {
                LegendRow(color: Palette.cyan, label: "基本工时", value: "")
                if showsPlanned {
                    LegendRow(color: Palette.purple, label: "计划工时", value: "")
                    LegendRow(color: Palette.orange.opacity(0.6), label: "额外", value: "")
                    LegendRow(color: Palette.red.opacity(0.5), label: "不足", value: "")
                }
                Spacer(minLength: 0)
            }
            Text("长按图表查看当月明细")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }
}
