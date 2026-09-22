import SwiftUI

/// 日历页：月度排班 + 本月展望。
///
/// 左右滑动切月交给 `MonthPager`（系统分页滚动，相邻月份跟着滑进来）；
/// 点月份标题可以直接跳到任意年月。
struct CalendarScreen: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast

    @State private var editingDate: String?
    @State private var isGeneratorPresented = false
    @State private var batchMode = false
    @State private var batchDates: Set<String> = []
    @State private var isBatchEditorPresented = false
    @State private var isPeriodPickerPresented = false

    /// 进出多选用的弹簧：略带一点回弹，行动条展开、网格下移、格子描边淡入都走这一条，
    /// 几样东西同一节奏动，看起来是一个整体在让位，而不是各动各的。
    private let batchAnimation = Animation.spring(response: 0.42, dampingFraction: 0.84)

    private var document: ScheduleDocument { store.document }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    monthPanel
                    nextShiftCard
                    outlookSection
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 20)
            }
            .background(Palette.canvas)
            .navigationTitle("循环班表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(batchAnimation) {
                            batchMode.toggle()
                            batchDates = []
                        }
                    } label: {
                        Label(batchMode ? "退出多选" : "批量修改",
                              systemImage: batchMode ? "xmark.circle" : "checklist")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isGeneratorPresented = true
                    } label: {
                        Label("循环排班", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .controlSize(.small)
                    .tint(Palette.blue)
                }
            }
            .sheet(item: Binding(get: { editingDate.map(DateKeyBox.init) },
                                 set: { editingDate = $0?.key })) { box in
                DayEditorSheet(date: box.key)
            }
            .sheet(isPresented: $isGeneratorPresented) {
                CycleGeneratorSheet()
            }
            .sheet(isPresented: $isBatchEditorPresented, onDismiss: {
                withAnimation(batchAnimation) {
                    batchDates = []
                    batchMode = false
                }
            }) {
                BatchEditorSheet(dates: batchDates.sorted())
            }
            .sheet(isPresented: $isPeriodPickerPresented) {
                let current = store.currentMonthIndex
                PeriodPickerSheet(mode: .month,
                                  selectedYear: store.focusedYear,
                                  selectedMonth: store.focusedMonth,
                                  currentYear: current / 12,
                                  currentMonth: current % 12) { year, month in
                    withAnimation(.smooth(duration: 0.3)) { store.focus(year: year, month: month) }
                }
            }
            .sensoryFeedback(.selection, trigger: store.focusedMonthKey)
        }
    }

    // MARK: - 月历

    private var monthPanel: some View {
        VStack(spacing: 0) {
            MonthSwitcher(label: store.focusedMonthLabel,
                          onPrevious: { changeMonth(-1) },
                          onNext: { changeMonth(1) },
                          onToday: {
                              withAnimation(.smooth(duration: 0.3)) { store.goToCurrentMonth() }
                          },
                          onPickLabel: { isPeriodPickerPresented = true })
                .padding(.bottom, 12)

            // 行动条一直在布局里，只是收起时高度为零并裁掉：展开时从上往下拉开，
            // 下面的网格跟着同一条弹簧平滑下移，而不是先整块顶下去再淡入。
            batchBar
                .padding(.bottom, 12)
                .frame(height: batchMode ? nil : 0, alignment: .top)
                .clipped()
                .opacity(batchMode ? 1 : 0)
                .scaleEffect(batchMode ? 1 : 0.96, anchor: .top)
                .allowsHitTesting(batchMode)
                .accessibilityHidden(!batchMode)

            MonthPager(focusedIndex: store.focusedIndex,
                       batchMode: batchMode,
                       selectedDates: batchDates,
                       onSelect: handleTap)

            Text("‹ 左右滑动切换月份 ›")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 12)
        }
        .card(cornerRadius: 22, padding: 14)
    }

    private func changeMonth(_ delta: Int) {
        withAnimation(.smooth(duration: 0.38)) {
            store.changeMonth(by: delta)
        }
    }

    /// 多选时的行动条。每一格都能单独勾选，勾完按「修改」。
    private var batchBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(batchDates.isEmpty ? "挑出要改的日子" : "已选 \(batchDates.count) 天")
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.numericText())
                Text(batchDates.isEmpty ? "点格子勾选，可以不连续" : "再点一次取消勾选")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button(isWholeMonthSelected ? "全不选" : "选整月") {
                withAnimation(.snappy(duration: 0.28)) {
                    if isWholeMonthSelected {
                        batchDates.subtract(monthDateKeys)
                    } else {
                        batchDates.formUnion(monthDateKeys)
                    }
                }
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)

            Button("修改") { isBatchEditorPresented = true }
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .controlSize(.regular)
                .tint(Palette.blue)
                .disabled(batchDates.isEmpty)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Palette.todayFill, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// 当前月份是不是已经整月勾上了。多选可以跨月，所以只看这个月的日子。
    private var isWholeMonthSelected: Bool {
        batchDates.isSuperset(of: monthDateKeys)
    }

    /// 当前月份的全部日期键，给「选整月」用。
    private var monthDateKeys: [String] {
        (1...ScheduleCalendar.daysInMonth(year: store.focusedYear, month: store.focusedMonth)).map {
            ScheduleCalendar.key(year: store.focusedYear, month: store.focusedMonth, day: $0)
        }
    }

    private func handleTap(_ date: String) {
        guard batchMode else {
            editingDate = date
            return
        }
        // 每一格独立开关，选完再按「修改」——不再是「先点起点、再点终点」那套
        withAnimation(.snappy(duration: 0.25)) {
            if batchDates.contains(date) {
                batchDates.remove(date)
            } else {
                batchDates.insert(date)
            }
        }
    }

    // MARK: - 下一班

    private var monthRecords: [DayRecord] {
        document.records.filter { $0.monthKey == store.focusedMonthKey }
    }

    private var workRecords: [DayRecord] {
        monthRecords.filter { document.shift($0.shiftId)?.countsAsWork == true }
    }

    private var upcoming: DayRecord? {
        document.records.first {
            $0.date >= store.todayKey && document.shift($0.shiftId)?.countsAsWork == true
        }
    }

    @ViewBuilder
    private var nextShiftCard: some View {
        if let upcoming, let shift = document.shift(upcoming.shiftId) {
            Button {
                editingDate = upcoming.date
            } label: {
                HStack(spacing: 12) {
                    ShiftOrb(shift: shift, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("下一班 · \(shift.name)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text(nextShiftDetail(upcoming, shift: shift))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .card(cornerRadius: 20, padding: 14)
            }
            .buttonStyle(.plain)
        } else {
            HStack(spacing: 12) {
                Image(systemName: "calendar")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("暂无后续班次").font(.subheadline.weight(.semibold))
                    Text("可逐日添加，或使用循环排班。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .card(cornerRadius: 20, padding: 14)
        }
    }

    private func nextShiftDetail(_ record: DayRecord, shift: ShiftDefinition) -> String {
        var parts = [relativeLabel(record.date)]
        if !shift.fullRange.isEmpty { parts.append(shift.fullRange) }
        if document.work.trackHours { parts.append("\(HoursFormatter.compact(record.hours)) 小时") }
        return parts.joined(separator: " · ")
    }

    /// 今天、明天、后天说人话，再远就写日期。
    private func relativeLabel(_ date: String) -> String {
        switch ScheduleCalendar.dayDifference(date, store.todayKey) {
        case 0: "今天"
        case 1: "明天"
        case 2: "后天"
        default: date
        }
    }

    // MARK: - 本月展望

    /// 与统计页 `basicDetail` 同一套措辞。
    private func basicDetail(planned: Double, basic: Double) -> String {
        let diff = planned - basic
        if diff > 0 { return "计划高出 \(HoursFormatter.hours(diff))" }
        if diff < 0 { return "计划少 \(HoursFormatter.hours(-diff))" }
        return "与基本工时持平"
    }

    private var outlookSection: some View {
        let restDays = monthRecords.filter { document.shift($0.shiftId)?.isRest == true }.count
        let completed = workRecords.filter { $0.countsAsCompleted(today: store.todayKey) }
        let projectedHours = workRecords.reduce(0) { $0 + $1.hours }
        let actualHours = completed.reduce(0) { $0 + $1.hours }
        let basic = WorkHours.monthlyTarget(document, year: store.focusedYear, month: store.focusedMonth)
        let overtime = WorkHours.overtimeForCalendarMonth(document,
                                                         year: store.focusedYear,
                                                         month: store.focusedMonth,
                                                         today: store.todayKey)

        return VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: document.work.trackHours ? "工时概览" : "出勤概览",
                          eyebrow: "本月",
                          badge: "\(workRecords.count) 个班")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                // 四块与统计页的「工时概览」一一对应，口径和配色都一致
                MetricTile(label: "出勤天数",
                           value: "\(workRecords.count)天",
                           detail: "休息 \(restDays) 天",
                           tint: Palette.green,
                           symbol: "calendar")
                if document.work.trackHours {
                    MetricTile(label: "计划工时",
                               value: HoursFormatter.hours(projectedHours),
                               detail: "已完成 \(HoursFormatter.hours(actualHours))",
                               tint: Palette.purple,
                               symbol: "clock")
                    MetricTile(label: "基本工时",
                               value: HoursFormatter.hours(basic),
                               detail: basicDetail(planned: projectedHours, basic: basic),
                               tint: Palette.cyan,
                               symbol: "target")
                }
                if document.work.trackHours && document.work.trackOvertime {
                    MetricTile(label: document.work.system == .comprehensive ? "本周期额外工时" : "本月额外工时",
                               value: HoursFormatter.hours(overtime.projected),
                               detail: "\(overtime.label) · 已确认 \(HoursFormatter.hours(overtime.actual))",
                               tint: Palette.orange,
                               symbol: "bolt")
                }
            }
        }
        .card(cornerRadius: 22, padding: 16)
    }
}

/// `sheet(item:)` 需要一个 Identifiable，日期字符串包一层。
struct DateKeyBox: Identifiable {
    let key: String
    var id: String { key }
}

/// 月份切换条。日历页和统计页共用：左右箭头逐期切换，点中间的标题弹出年月选择器。
struct MonthSwitcher: View {
    let label: String
    var previousLabel = "上个月"
    var nextLabel = "下个月"
    var todayTitle = "今天"
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void
    var onPickLabel: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left").font(.footnote.weight(.bold))
            }
            .buttonStyle(SecondaryButton())
            .accessibilityLabel(previousLabel)

            Button {
                onPickLabel?()
            } label: {
                HStack(spacing: 4) {
                    Text(label)
                        .font(.title3.weight(.bold))
                        .contentTransition(.numericText())
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if onPickLabel != nil {
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(onPickLabel == nil)
            .accessibilityHint(onPickLabel == nil ? "" : "选择年月")

            Button(action: onNext) {
                Image(systemName: "chevron.right").font(.footnote.weight(.bold))
            }
            .buttonStyle(SecondaryButton())
            .accessibilityLabel(nextLabel)

            Button(todayTitle, action: onToday)
                .buttonStyle(SecondaryButton(tint: Palette.green))
        }
    }
}
