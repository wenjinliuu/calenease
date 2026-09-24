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
        // 玻璃小卡：隐约透出底下的曲线
        .glassCard(cornerRadius: 12)
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
/// 两条线都是平滑曲线（单调三次插值：过每个月的点，两点之间不会冲过头），
/// 曲线和面积由同一个插值函数算出来，自己画在图表的底层 / 上层；Swift Charts 只负责坐标轴、
/// 月份上的圆点和长按提示。之前面积交给 `AreaMark` 按月份的点连折线，
/// 和曲线对不上，交叉那一段颜色也不对。
///
/// 计划高出基本的部分填橙色，低于基本的部分填红色。面积按细小的横向切片逐片填色，
/// 切片里两条曲线交叉时在交点处分开，两种颜色各归各的，交叉处不会串色。
struct HoursTrendChart: View, Equatable {
    struct Point: Hashable, Identifiable {
        let index: Int
        let label: String
        let basic: Double
        let planned: Double
        var id: Int { index }
    }

    let points: [Point]
    let showsPlanned: Bool

    @State private var selectedIndex: Int?

    nonisolated static func == (lhs: HoursTrendChart, rhs: HoursTrendChart) -> Bool {
        lhs.points == rhs.points && lhs.showsPlanned == rhs.showsPlanned
    }

    /// 排了班的月份。没排班的月份不画计划线，否则会和基本工时线重合。
    private var scheduled: [Point] { points.filter { $0.planned > 0 } }

    /// 计划曲线按连续排了班的月份分段：中间隔着没排班的月份就断开。
    static func segments(_ scheduled: [Point]) -> [[Point]] {
        var result: [[Point]] = []
        for point in scheduled {
            if let last = result.last?.last, point.index - last.index == 1 {
                result[result.count - 1].append(point)
            } else {
                result.append([point])
            }
        }
        return result
    }

    var body: some View {
        let scheduled = scheduled
        let selected = selectedIndex.flatMap { index in points.first { $0.index == index } }
        let lastIndex = Double(max(points.count - 1, 0))
        let basicCurve = MonotoneCurve(xs: points.map { Double($0.index) }, ys: points.map(\.basic))
        let plannedCurves = showsPlanned
            ? Self.segments(scheduled).map { segment in
                MonotoneCurve(xs: segment.map { Double($0.index) }, ys: segment.map(\.planned))
            }
            : []

        VStack(alignment: .leading, spacing: 14) {
            Chart {
                // 透明的点只用来撑开纵轴范围；单调插值不越过数据点，曲线不会跑出这个范围
                ForEach(points) { point in
                    PointMark(x: .value("月份", Double(point.index)), y: .value("基本工时", point.basic))
                        .foregroundStyle(.clear)
                }

                // 计划工时也只撑纵轴范围、不画点：计划线就是一条干净的平滑曲线
                if showsPlanned {
                    ForEach(scheduled) { point in
                        PointMark(x: .value("月份", Double(point.index)),
                                  y: .value("计划工时", point.planned))
                            .foregroundStyle(.clear)
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
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let origin = geometry[plotFrame].origin
                        TrendFills(proxy: proxy, origin: origin, basic: basicCurve, planned: plannedCurves)
                    }
                }
                .allowsHitTesting(false)
            }
            .chartXScale(domain: 0...max(lastIndex, 1))
            // 长按 0.3 秒选中，按住左右拖换月份，松手收起。只在换到另一个月时才更新状态，
            // 手指在同一个月里挪动不触发重画。
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        TrendLines(proxy: proxy, origin: geometry[plotFrame].origin,
                                   basic: basicCurve, planned: plannedCurves)
                            .allowsHitTesting(false)
                    }
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

/// 单调三次插值（Fritsch–Carlson）：曲线过每一个数据点，相邻两点之间不会冲过头，
/// 所以不会凭空画出比哪个月都高或都低的波峰。
struct MonotoneCurve {
    let xs: [Double]
    let ys: [Double]
    private let slopes: [Double]

    init(xs: [Double], ys: [Double]) {
        self.xs = xs
        self.ys = ys
        let n = xs.count
        guard n > 1 else {
            slopes = [Double](repeating: 0, count: n)
            return
        }
        // 相邻两点的斜率
        var d = [Double](repeating: 0, count: n - 1)
        for k in 0..<(n - 1) {
            let run: Double = max(xs[k + 1] - xs[k], 1e-9)
            let rise: Double = ys[k + 1] - ys[k]
            d[k] = rise / run
        }
        // 每个点的切线：两侧斜率同号取平均，异号（拐点）取 0
        var m = [Double](repeating: 0, count: n)
        m[0] = d[0]
        m[n - 1] = d[n - 2]
        if n > 2 {
            for k in 1..<(n - 1) {
                let left: Double = d[k - 1]
                let right: Double = d[k]
                m[k] = left * right <= 0 ? 0 : (left + right) / 2
            }
        }
        // Fritsch–Carlson：切线太陡就按比例压下来，保证不冲过头
        for k in 0..<(n - 1) {
            let slope: Double = d[k]
            if slope == 0 {
                m[k] = 0
                m[k + 1] = 0
                continue
            }
            let a: Double = m[k] / slope
            let b: Double = m[k + 1] / slope
            let length: Double = a * a + b * b
            if length > 9 {
                let t: Double = 3 / length.squareRoot()
                m[k] = t * a * slope
                m[k + 1] = t * b * slope
            }
        }
        slopes = m
    }

    var isEmpty: Bool { xs.isEmpty }
    var range: ClosedRange<Double> { (xs.first ?? 0)...(xs.last ?? 0) }

    func value(at x: Double) -> Double {
        guard let first = xs.first, let last = xs.last else { return 0 }
        if xs.count == 1 || x <= first { return ys[0] }
        if x >= last { return ys[ys.count - 1] }
        var k = 0
        while k < xs.count - 2 && x > xs[k + 1] { k += 1 }
        let h: Double = xs[k + 1] - xs[k]
        let t: Double = (x - xs[k]) / h
        let t2: Double = t * t
        let t3: Double = t2 * t
        // 三次 Hermite 基函数
        let h00: Double = 2 * t3 - 3 * t2 + 1
        let h10: Double = t3 - 2 * t2 + t
        let h01: Double = -2 * t3 + 3 * t2
        let h11: Double = t3 - t2
        let start: Double = h00 * ys[k] + h10 * h * slopes[k]
        let end: Double = h01 * ys[k + 1] + h11 * h * slopes[k + 1]
        return start + end
    }

    /// 在 [lower, upper] 上等距取样，每个月之间取 `density` 个点。
    func samples(from lower: Double, to upper: Double, density: Int = 24) -> [Double] {
        guard upper > lower else { return [lower] }
        let count = max(2, Int(((upper - lower) * Double(density)).rounded(.up)) + 1)
        return (0..<count).map { lower + (upper - lower) * Double($0) / Double(count - 1) }
    }
}

/// 图表底层：基本工时下面一层淡青渐变，计划与基本之间的橙 / 红面积。
private struct TrendFills: View {
    let proxy: ChartProxy
    let origin: CGPoint
    let basic: MonotoneCurve
    let planned: [MonotoneCurve]

    var body: some View {
        Canvas { context, _ in
            guard !basic.isEmpty else { return }
            func point(_ x: Double, _ y: Double) -> CGPoint? {
                proxy.position(for: (x: x, y: y)).map { CGPoint(x: $0.x + origin.x, y: $0.y + origin.y) }
            }

            // 基本工时下方的渐变
            let xs = basic.samples(from: basic.range.lowerBound, to: basic.range.upperBound)
            var base = Path()
            let bottom = origin.y + proxy.plotSize.height
            if let first = point(xs[0], basic.value(at: xs[0])) {
                base.move(to: CGPoint(x: first.x, y: bottom))
                for x in xs { if let p = point(x, basic.value(at: x)) { base.addLine(to: p) } }
                if let last = point(xs[xs.count - 1], basic.value(at: xs[xs.count - 1])) {
                    base.addLine(to: CGPoint(x: last.x, y: bottom))
                }
                base.closeSubpath()
                context.fill(base, with: .linearGradient(
                    Gradient(colors: [Palette.cyan.opacity(0.26), Palette.cyan.opacity(0.03)]),
                    startPoint: CGPoint(x: 0, y: origin.y), endPoint: CGPoint(x: 0, y: bottom)))
            }

            // 计划与基本之间：逐片填色，片内交叉就在交点处一分为二
            var over = Path()
            var under = Path()
            for curve in planned where curve.xs.count > 1 {
                let xs = curve.samples(from: curve.range.lowerBound, to: curve.range.upperBound)
                for (x0, x1) in zip(xs, xs.dropFirst()) {
                    let p0 = curve.value(at: x0), p1 = curve.value(at: x1)
                    let b0 = basic.value(at: x0), b1 = basic.value(at: x1)
                    let d0 = p0 - b0, d1 = p1 - b1
                    func piece(_ xa: Double, _ pa: Double, _ ba: Double,
                               _ xb: Double, _ pb: Double, _ bb: Double, into path: inout Path) {
                        guard let a1 = point(xa, pa), let a2 = point(xb, pb),
                              let c2 = point(xb, bb), let c1 = point(xa, ba) else { return }
                        path.move(to: a1)
                        path.addLine(to: a2)
                        path.addLine(to: c2)
                        path.addLine(to: c1)
                        path.closeSubpath()
                    }
                    if d0 * d1 < 0 {
                        let t = d0 / (d0 - d1)
                        let xc = x0 + (x1 - x0) * t
                        let yc = b0 + (b1 - b0) * t
                        if d0 > 0 {
                            piece(x0, p0, b0, xc, yc, yc, into: &over)
                            piece(xc, yc, yc, x1, p1, b1, into: &under)
                        } else {
                            piece(x0, p0, b0, xc, yc, yc, into: &under)
                            piece(xc, yc, yc, x1, p1, b1, into: &over)
                        }
                    } else if d0 + d1 > 0 {
                        piece(x0, p0, b0, x1, p1, b1, into: &over)
                    } else if d0 + d1 < 0 {
                        piece(x0, p0, b0, x1, p1, b1, into: &under)
                    }
                }
            }
            context.fill(over, with: .color(Palette.orange.opacity(0.32)))
            context.fill(under, with: .color(Palette.red.opacity(0.34)))
        }
    }
}

/// 图表上层：基本（青）、计划（紫）两条平滑曲线。
private struct TrendLines: View {
    let proxy: ChartProxy
    let origin: CGPoint
    let basic: MonotoneCurve
    let planned: [MonotoneCurve]

    var body: some View {
        Canvas { context, _ in
            func path(_ curve: MonotoneCurve) -> Path {
                var path = Path()
                guard !curve.isEmpty else { return path }
                let xs = curve.samples(from: curve.range.lowerBound, to: curve.range.upperBound)
                for (offset, x) in xs.enumerated() {
                    guard let p = proxy.position(for: (x: x, y: curve.value(at: x))) else { continue }
                    let point = CGPoint(x: p.x + origin.x, y: p.y + origin.y)
                    if offset == 0 { path.move(to: point) } else { path.addLine(to: point) }
                }
                return path
            }
            context.stroke(path(basic), with: .color(Palette.cyan),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            for curve in planned where curve.xs.count > 1 {
                context.stroke(path(curve), with: .color(Palette.purple),
                               style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
