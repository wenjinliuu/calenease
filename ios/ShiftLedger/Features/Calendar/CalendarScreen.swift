import SwiftUI

/// 日历页：月度排班 + 本月展望。
///
/// 左右拖动切月：手指按住时整块日历 1:1 跟手，越界处递减阻尼；
/// 松手按投影位置决定切换还是弹回，收尾用临界阻尼弹簧，中途可以随时抓回。
struct CalendarScreen: View {
    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast

    @State private var editingDate: String?
    @State private var isGeneratorPresented = false
    @State private var batchMode = false
    @State private var batchDates: [String] = []
    @State private var isBatchEditorPresented = false
    @State private var dragOffset: CGFloat = 0
    @State private var slideEdge: Edge = .trailing

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
                        withAnimation(.spring(response: 0.3, dampingFraction: 1)) {
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
                        Label("循环排班", systemImage: "arrow.trianglehead.2.clockwise.rotate.90")
                    }
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
                batchDates = []
                batchMode = false
            }) {
                BatchEditorSheet(dates: batchDates)
            }
            .sensoryFeedback(.selection, trigger: store.focusedMonthKey)
        }
    }

    // MARK: - 月历

    private var monthPanel: some View {
        VStack(spacing: 12) {
            MonthSwitcher(label: store.focusedMonthLabel,
                          onPrevious: { changeMonth(-1) },
                          onNext: { changeMonth(1) },
                          onToday: {
                              slideEdge = store.isFocusedBefore(today: true) ? .trailing : .leading
                              withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) {
                                  store.goToCurrentMonth()
                              }
                          })

            if batchMode { batchHint }

            GeometryReader { proxy in
                CalendarMonthGrid(year: store.focusedYear,
                                  month: store.focusedMonth,
                                  document: document,
                                  todayKey: store.todayKey,
                                  batchMode: batchMode,
                                  batchDates: batchDates,
                                  onSelect: handleTap)
                    .id(store.focusedMonthKey)
                    .transition(.asymmetric(
                        insertion: .move(edge: slideEdge).combined(with: .opacity),
                        removal: .move(edge: slideEdge == .trailing ? .leading : .trailing).combined(with: .opacity)
                    ))
                    .offset(x: dragOffset)
                    // 和纵向滚动共存：手势自己判断方向，纵向的交回给 ScrollView
                    .simultaneousGesture(monthDrag(width: proxy.size.width))
            }
            .frame(height: gridHeight)
            .clipped()

            Text("‹ 左右滑动切换月份 ›")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    /// 网格高度随行数和显示开关变化，提前算好，避免拖动时高度跳变。
    private var gridHeight: CGFloat {
        let blanks = ScheduleCalendar.leadingBlanks(year: store.focusedYear, month: store.focusedMonth)
        let days = ScheduleCalendar.daysInMonth(year: store.focusedYear, month: store.focusedMonth)
        let rows = CGFloat((blanks + days + 6) / 7)
        let cell = DayCellMetrics.height(for: document.display)
        // 星期表头 + 表头间距 + 每行格子与行距
        return 13 + 10 + rows * cell + (rows - 1) * DayCellMetrics.rowSpacing
    }

    private func monthDrag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 14)
            .onChanged { value in
                guard !batchMode, isHorizontal(value.translation) else { return }
                dragOffset = rubberband(value.translation.width, limit: width)
            }
            .onEnded { value in
                guard !batchMode, isHorizontal(value.translation) else {
                    dragOffset = 0
                    return
                }
                // 用速度把落点投影出去，快速轻扫也能切月
                let projected = value.translation.width + value.velocity.width * 0.12
                if projected < -width * 0.28 {
                    changeMonth(1)
                } else if projected > width * 0.28 {
                    changeMonth(-1)
                } else {
                    withAnimation(.spring(response: 0.32, dampingFraction: 1)) { dragOffset = 0 }
                }
            }
    }

    /// 明显偏水平才算切月，否则这一下是在纵向滚页面。
    private func isHorizontal(_ translation: CGSize) -> Bool {
        abs(translation.width) > abs(translation.height) * 1.4
    }

    /// 越界后递减跟手，靠近边界像被拉住而不是撞墙。
    private func rubberband(_ offset: CGFloat, limit: CGFloat) -> CGFloat {
        let constant: CGFloat = 0.55
        let magnitude = abs(offset)
        let damped = (magnitude * limit * constant) / (limit + constant * magnitude)
        return offset < 0 ? -damped : damped
    }

    private func changeMonth(_ delta: Int) {
        slideEdge = delta > 0 ? .trailing : .leading
        withAnimation(.spring(response: 0.34, dampingFraction: 0.92)) {
            dragOffset = 0
            store.changeMonth(by: delta)
        }
    }

    private var batchHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.dashed.inset.filled")
                .foregroundStyle(Palette.blue)
            VStack(alignment: .leading, spacing: 2) {
                Text(batchDates.isEmpty ? "请选择起始日期" : "起点：\(batchDates[0])")
                    .font(.subheadline.weight(.semibold))
                Text(batchDates.isEmpty ? "单日修改不会影响后续循环" : "再选截止日，将统一修改整个区间")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Palette.blue.opacity(0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func handleTap(_ date: String) {
        guard batchMode else {
            editingDate = date
            return
        }
        if batchDates.isEmpty {
            batchDates = [date]
        } else {
            batchDates = ScheduleCalendar.range(batchDates[0], date)
            isBatchEditorPresented = true
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
                .raisedCard(cornerRadius: 20, padding: 14)
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
            .raisedCard(cornerRadius: 20, padding: 14)
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
            SectionHeader(title: document.work.trackHours ? "排班与累计工时" : "我的班表",
                          eyebrow: "本月展望",
                          badge: "\(workRecords.count) 个工作日")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                      spacing: 10) {
                MetricTile(label: "计划工作日",
                           value: "\(workRecords.count)天",
                           detail: "\(restDays) 个休息日",
                           tint: Palette.blue,
                           symbol: "calendar")
                MetricTile(label: "已完成班次",
                           value: "\(completed.count)天",
                           detail: "剩余 \(max(0, workRecords.count - completed.count)) 个班次",
                           tint: Palette.green,
                           symbol: "checkmark.circle")
                if document.work.trackHours {
                    MetricTile(label: "本月计划工时",
                               value: HoursFormatter.hours(projectedHours),
                               detail: "基本工时 \(HoursFormatter.hours(basic)) · 已完成 \(HoursFormatter.hours(actualHours))",
                               tint: Palette.purple,
                               symbol: "clock")
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
        .raisedCard(cornerRadius: 22, padding: 16)
    }
}

/// `sheet(item:)` 需要一个 Identifiable，日期字符串包一层。
struct DateKeyBox: Identifiable {
    let key: String
    var id: String { key }
}

/// 月份切换条。
struct MonthSwitcher: View {
    let label: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onToday: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left").font(.footnote.weight(.bold))
            }
            .buttonStyle(SecondaryButton())
            .accessibilityLabel("上个月")

            Text(label)
                .font(.title3.weight(.bold))
                .contentTransition(.numericText())
                .monospacedDigit()
                .frame(maxWidth: .infinity)

            Button(action: onNext) {
                Image(systemName: "chevron.right").font(.footnote.weight(.bold))
            }
            .buttonStyle(SecondaryButton())
            .accessibilityLabel("下个月")

            Button("今天", action: onToday)
                .buttonStyle(SecondaryButton(tint: Palette.green))
        }
    }
}
