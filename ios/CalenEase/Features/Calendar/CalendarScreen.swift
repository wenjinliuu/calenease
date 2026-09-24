import SwiftUI

/// 日历页。
///
/// 顶上一行简化标题：左边大字月份（不是今年再带一个小年份），点它跳到任意年月日；
/// 右边是「今天」、多选、循环排班。下面整宽的月历，再往下是选中那一天的面板、
/// 下一班和倒数日。
///
/// 点格子分两步：第一下只是选中（蓝圈），再点一下选中的那天才打开大抽屉。
/// 打开 App 时今天已经是选中的，所以点今天一下就直接进编辑。
/// 左右翻月不会改选中的日子，下面的面板一直是用户最后点的那一天。
struct CalendarScreen: View {
    @Environment(ScheduleStore.self) private var store

    @State private var selectedDate: String = ScheduleCalendar.todayKey
    @State private var sheet: CalendarSheet?
    @State private var isGeneratorPresented = false
    @State private var batchMode = false
    @State private var batchDates: Set<String> = []
    @State private var isBatchEditorPresented = false
    /// 点格子选中时震一下。翻月自动选 1 号时月份那边已经震过了，不再叠一次。
    @State private var tapTick = 0
    /// 标题上显示的月份。跟着 store 的月份走，但自己带动画：翻页提交月份时为了卡片不跳，
    /// 那一下是关掉动画的，标题要是直接读 store，数字滚动的动效就被一起关掉了。
    @State private var titleIndex: Int?
    @State private var sparkleTick = 0

    /// 进出多选用的弹簧：略带一点回弹，行动条展开、网格下移、格子描边淡入都走这一条，
    /// 几样东西同一节奏动，看起来是一个整体在让位，而不是各动各的。
    private let batchAnimation = Animation.spring(response: 0.42, dampingFraction: 0.84)

    private var document: ScheduleDocument { store.document }
    private var shiftsEnabled: Bool { document.features.shiftsEnabled }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    VStack(spacing: 0) {
                        MonthPager(focusedIndex: store.focusedIndex,
                                   batchMode: batchMode,
                                   selectedDates: batchDates,
                                   selectedDay: selectedDate,
                                   onSelect: handleTap)
                            .padding(.horizontal, 6)
                    }

                    VStack(spacing: 14) {
                        DayPanel(date: selectedDate,
                                 onEditShift: { sheet = .day(selectedDate, .shift) },
                                 onOpenEvents: { sheet = .day(selectedDate, .events) },
                                 onEditEvent: { sheet = .event(.edit($0)) },
                                 onNewEvent: { sheet = .event(.new(on: selectedDate, reminders: document.reminders)) },
                                 onTimeline: { sheet = .timeline(selectedDate) })
                        CountdownSection { countdown in
                            sheet = .countdown(countdown)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                .padding(.top, 2)
                .padding(.bottom, 24)
            }
            // 和「工时」「设置」同一种顶栏：系统导航栏 + 系统玻璃按钮 + 系统滚动边缘效果。
            // 多选行动条挂在导航栏下（safeAreaBar），算顶栏的一部分。
            .safeAreaBar(edge: .top, spacing: 0) { batchBarSlot }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .sheet(item: $sheet) { item in
                switch item {
                case let .day(date, segment):
                    DayEditorSheet(date: date, initialSegment: segment)
                case let .event(target):
                    EventEditorSheet(target: target)
                case let .timeline(date):
                    DayTimelineSheet(startDate: date)
                case let .countdown(countdown):
                    CountdownEditorSheet(original: countdown, today: store.todayKey)
                case .jump:
                    DateJumpSheet(initial: selectedDate) { date in jump(to: date) }
                }
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
            .sensoryFeedback(.selection, trigger: store.focusedMonthKey)
            .sensoryFeedback(.selection, trigger: tapTick)
            // 翻到别的月不自动选日子：选中的那天留在原处，用户点了才算选。
            .onChange(of: store.focusedIndex) { _, index in
                withAnimation(.snappy(duration: 0.3)) { titleIndex = index }
            }
            .onChange(of: shiftsEnabled) { _, enabled in
                if !enabled {
                    batchMode = false
                    batchDates = []
                }
            }
        }
    }

    // MARK: - 标题行

    /// 行动条一直在布局里，只是收起时高度为零并裁掉：展开时从上往下拉开，
    /// 下面的网格跟着同一条弹簧平滑下移，而不是先整块顶下去再淡入。
    private var batchBarSlot: some View {
        batchBar
            .padding(.horizontal, 12)
            .padding(.top, 4)
            .padding(.bottom, 10)
            .frame(height: batchMode ? nil : 0, alignment: .top)
            .clipped()
            .opacity(batchMode ? 1 : 0)
            .scaleEffect(batchMode ? 1 : 0.96, anchor: .top)
            .allowsHitTesting(batchMode)
            .accessibilityHidden(!batchMode)
    }

    /// 右上角从左到右：循环排班、多选、回到今天。「今天」放在最右边，和事项页同一个位置。
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { monthTitle }
            .sharedBackgroundVisibility(.hidden)
        if shiftsEnabled {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    sparkleTick += 1
                    isGeneratorPresented = true
                } label: {
                    // 和其他按钮一样的黑色图标；点一下星星按层弹一下，由操作触发，不做循环的装饰动画
                    Image(systemName: "sparkles")
                        .foregroundStyle(.primary)
                        .symbolEffect(.bounce.up.byLayer, options: .speed(1.4), value: sparkleTick)
                }
                .accessibilityLabel("循环排班")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(batchAnimation) {
                        batchMode.toggle()
                        batchDates = []
                    }
                } label: {
                    // 图标原地变形（清单 ⇄ 叉），不是整颗按钮一闪换掉
                    Image(systemName: batchMode ? "xmark" : "checklist")
                        .contentTransition(.symbolEffect(.replace.downUp.byLayer, options: .nonRepeating))
                        .foregroundStyle(batchMode ? Palette.blue : Color.primary)
                }
                .accessibilityLabel(batchMode ? "退出多选" : "批量修改")
                .sensoryFeedback(.impact(weight: .light), trigger: batchMode)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                jump(to: store.todayKey)
            } label: {
                TodayBadge(day: Int(store.todayKey.suffix(2)) ?? 1)
            }
            .accessibilityLabel("回到今天")
        }
    }

    private var monthTitle: some View {
        let index = titleIndex ?? store.focusedIndex
        let year = index / 12, month = index % 12
        return Button { sheet = .jump } label: {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                // 和事项页左上角的月份同一种数字滚动
                Text("\(month + 1)")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(index)))
                Text("月")
                    .font(.headline.weight(.bold))
                if year != store.currentMonthIndex / 12 {
                    Text("\(String(year))年")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                        .transition(.opacity.combined(with: .move(edge: .leading)))
                }
                Image(systemName: "chevron.down")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 2)
            }
            .foregroundStyle(.primary)
            .fixedSize()
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.focusedMonthLabel)
        .accessibilityHint("跳到任意日期")
    }

    /// 跳到某一天：选中它，月历翻过去。
    private func jump(to date: String) {
        guard let parts = ScheduleCalendar.components(from: date) else { return }
        selectedDate = date
        withAnimation(.smooth(duration: 0.3)) { store.focus(year: parts.year, month: parts.month) }
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
            // 第一下选中，再点一下已选中的那天才打开抽屉
            if date == selectedDate {
                sheet = .day(date, shiftsEnabled ? .shift : .events)
            } else {
                withAnimation(.snappy(duration: 0.2)) { selectedDate = date }
                tapTick += 1
            }
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

    /// 今天、明天、后天说人话，再远就写日期。
    static func relativeLabel(_ date: String, today: String) -> String {
        switch ScheduleCalendar.dayDifference(date, today) {
        case 0: "今天"
        case 1: "明天"
        case 2: "后天"
        case -1: "昨天"
        case -2: "前天"
        default: date
        }
    }
}

/// 日历页弹出来的几种抽屉。
enum CalendarSheet: Identifiable {
    case day(String, DaySegment)
    case event(EventEditorTarget)
    case timeline(String)
    case countdown(Countdown?)
    case jump

    var id: String {
        switch self {
        case let .day(date, segment): "day-\(date)-\(segment.rawValue)"
        case let .event(target): "event-\(target.id)"
        case let .timeline(date): "timeline-\(date)"
        case let .countdown(countdown): "countdown-\(countdown?.id ?? "new")"
        case .jump: "jump"
        }
    }
}

/// 选中那一天的面板：节日 / 休班、日期与农历、当天班次、当天日程。
private struct DayPanel: View {
    let date: String
    let onEditShift: () -> Void
    let onOpenEvents: () -> Void
    let onEditEvent: (EventOccurrence) -> Void
    let onNewEvent: () -> Void
    let onTimeline: () -> Void

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    /// 哪一条日程正左滑开着，同一时间只开一条。
    @State private var openRow: String?

    var body: some View {
        let document = store.document
        let occurrences = store.occurrences(on: date)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(dateTitle)
                            .font(.headline)
                            .monospacedDigit()
                            .contentTransition(.numericText(value: Double(DayNumber.of(date) ?? 0)))
                        badges
                    }
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText(value: Double(DayNumber.of(date) ?? 0)))
                }
                Spacer(minLength: 0)
                Button(action: onTimeline) {
                    Image(systemName: "calendar.day.timeline.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 34, height: 34)
                        .background(Palette.inset, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("时间轴")
            }

            if document.features.shiftsEnabled {
                shiftRow(document)
            }

            if occurrences.isEmpty {
                Text("这天还没有日程")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
            } else {
                VStack(spacing: 6) {
                    ForEach(occurrences) { occurrence in
                        // 和事项页一样：右边打勾完成（两边同步），左滑编辑 / 删除
                        SwipeActionsRow(id: occurrence.id, openRow: $openRow,
                                        onEdit: { onEditEvent(occurrence) },
                                        onDelete: { delete(occurrence) },
                                        cornerRadius: 12) {
                            HStack(spacing: 8) {
                                Button { onEditEvent(occurrence) } label: {
                                    EventRow(occurrence: occurrence, day: date, showsDoneMark: false)
                                }
                                .buttonStyle(.plain)
                                Button {
                                    withAnimation(.snappy(duration: 0.25)) {
                                        store.toggleCompletion(eventId: occurrence.event.id, on: occurrence.startKey)
                                    }
                                } label: {
                                    Image(systemName: occurrence.isCompleted ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 22))
                                        .foregroundStyle(Tone.event(occurrence.event.color).solid)
                                        .contentTransition(.symbolEffect(.replace))
                                        .frame(width: 32, height: 32)
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(occurrence.isCompleted ? "标记为未完成" : "标记为完成")
                                .sensoryFeedback(.success, trigger: occurrence.isCompleted) { _, new in new }
                            }
                            .padding(.leading, 10)
                            .padding(.trailing, 4)
                            .padding(.vertical, 6)
                            .background(Palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                    }
                }
            }

            Button(action: onNewEvent) {
                Label("新建日程", systemImage: "plus")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
                    .background(Palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .card(cornerRadius: 22, padding: 14)
        .animation(.snappy(duration: 0.25), value: date)
    }

    /// 重复日程左滑删掉的只是这一次，单次日程整条删掉。
    private func delete(_ occurrence: EventOccurrence) {
        let repeating = occurrence.event.recurrence.isRepeating
        withAnimation(.snappy(duration: 0.28)) {
            if repeating {
                store.excludeOccurrence(eventId: occurrence.event.id, on: occurrence.startKey)
            } else {
                store.deleteEvent(id: occurrence.event.id)
            }
        }
        showToast(repeating ? "已删除这一次" : "已删除日程", symbol: "trash")
    }

    @ViewBuilder
    private func shiftRow(_ document: ScheduleDocument) -> some View {
        let record = store.record(on: date)
        let shift = record.flatMap { $0.planned ? document.shift($0.shiftId) : nil }
        Button(action: onEditShift) {
            HStack(spacing: 10) {
                if let shift, let record {
                    ShiftOrb(shift: shift, size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 4) {
                            Text(shift.name).font(.subheadline.weight(.semibold))
                            if let secondary = record.secondaryShiftId.flatMap({ document.shift($0) }) {
                                Text("+ \(secondary.name)")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Text(shiftDetail(shift, record: record, document: document))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Image(systemName: "calendar.badge.plus")
                        .font(.body)
                        .foregroundStyle(Palette.blue)
                        .frame(width: 30, height: 30)
                    Text("未排班 · 点这里安排")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Palette.inset, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func shiftDetail(_ shift: ShiftDefinition, record: DayRecord, document: ScheduleDocument) -> String {
        var parts: [String] = []
        let range = record.fullRange(for: shift)
        if !range.isEmpty { parts.append(record.hasCustomTime ? "\(range)（当天调整）" : range) }
        if document.work.trackHours, shift.countsAsWork, !shift.isRest {
            parts.append("\(HoursFormatter.compact(record.hours)) 小时")
        }
        let tags = record.tagIds.compactMap { document.tag($0)?.name }
        if !tags.isEmpty { parts.append(tags.joined(separator: "、")) }
        if let note = record.note, !note.isEmpty { parts.append(note) }
        return parts.isEmpty ? "点这里修改" : parts.joined(separator: " · ")
    }

    private var dateTitle: String {
        guard let parts = ScheduleCalendar.components(from: date) else { return date }
        let weekday = ScheduleCalendar.weekdaySymbols[ScheduleCalendar.weekdayIndex(date)]
        return "\(parts.month + 1)月\(parts.day)日 周\(weekday)"
    }

    private var subtitle: String {
        var parts = ["农历" + LunarCalendar.fullText(for: date)]
        let relative = CalendarScreen.relativeLabel(date, today: store.todayKey)
        if relative != date { parts.insert(relative, at: 0) }
        return parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var badges: some View {
        if let festival = Festivals.festival(on: date) {
            Text(festival.name)
                .font(.caption2.weight(.bold))
                .foregroundStyle(festival.kind == .statutory ? Palette.holiday : Palette.traditionalFestival)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Palette.inset, in: Capsule())
        }
        switch store.holidays.adjustment(on: date) {
        case .off:
            Text("休")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Palette.holiday, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .work:
            Text("班")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(Palette.adjustedWorkday, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
        case nil:
            EmptyView()
        }
    }
}

/// 点标题的月份弹出来：滚轮选年月日，一步跳过去。
private struct DateJumpSheet: View {
    let onPick: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var date: Date

    init(initial: String, onPick: @escaping (String) -> Void) {
        self.onPick = onPick
        _date = State(initialValue: ScheduleCalendar.date(from: initial) ?? Date())
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker("日期", selection: $date, displayedComponents: [.date])
                    .datePickerStyle(.wheel)
                    .labelsHidden()
                    .environment(\.locale, Locale(identifier: "zh_CN"))
                    .environment(\.calendar, ScheduleCalendar.calendar)

                Button("跳到这一天") {
                    onPick(ScheduleCalendar.key(date))
                    dismiss()
                }
                .buttonStyle(ProminentButton())
                .padding(.horizontal, 20)
            }
            .padding(.top, 8)
            .navigationTitle("跳转日期")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("今天") {
                        onPick(ScheduleCalendar.todayKey)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(380)])
        .presentationDragIndicator(.visible)
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
