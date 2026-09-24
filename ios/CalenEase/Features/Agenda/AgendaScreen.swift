import SwiftUI

/// 事项页：所有日程按日、周两种方式看，有点像 Outlook 的日历。
///
/// - 日：顶上一排一周的日期，下面一天一段竖着往下排，上下滑时顶上的日期跟着走；
///   点顶上的日期，下面滑到那一天。今天那一段里有一条「现在」的红线。
///   当天的班次是日期标题后面的一枚小徽章，不和日程排成一样的条目。
/// - 周：周一到周日七列共用一条时间轴，左右滑动翻周，时间刻度不跟着翻页错开。
///
/// 月视图去掉了：日历页本身就是月视图。两种视图共用同一个「选中的日子」。
struct AgendaScreen: View {
    /// 再点一次「事项」标签时加一：回到今天，列表重新定位到今天那一段。
    var resetToken = 0

    @Environment(ScheduleStore.self) private var store

    @AppStorage("agenda.mode") private var modeRaw = AgendaMode.day.rawValue
    @State private var day: Int = DayNumber.of(ScheduleCalendar.todayKey) ?? 0
    @State private var editorTarget: EventEditorTarget?
    /// 换一个值就重建日视图列表。再点「事项」标签时，系统会把列表滚到最顶上
    /// （一年前那一天），看起来像跳到了不知道哪一天；直接换一个新列表、定位到今天，不和它抢。
    @State private var listID = 0

    private var mode: AgendaMode { AgendaMode(rawValue: modeRaw) ?? .day }
    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .day:
                    AgendaDayList(day: $day, onEdit: open)
                        .id(listID)
                case .week:
                    AgendaWeekView(day: $day, onEdit: open)
                        .id(listID)
                }
            }
            // 顶栏和「工时」「设置」一样用系统导航栏：同一种玻璃按钮、同一种滚动边缘效果。
            // 下面那一排日期挂在导航栏下（safeAreaBar），算顶栏的一部分，内容从它们底下一起滑过去。
            .safeAreaBar(edge: .top, spacing: 0) { dateStrip }
            .background(Palette.canvas)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
            .overlay(alignment: .bottomTrailing) { addButton }
            .sheet(item: $editorTarget) { target in
                EventEditorSheet(target: target)
            }
            .onChange(of: resetToken) { _, _ in
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) {
                    day = today
                    listID += 1
                }
                // 系统的「点标签回到顶部」动画要是晚一拍落到新列表上，再定位一次今天
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                    if day != today { withAnimation(.smooth(duration: 0.3)) { day = today } }
                }
            }
        }
    }

    private func open(_ target: EventEditorTarget) { editorTarget = target }

    // MARK: - 顶栏

    /// 本周那一排日期。日视图铺满一行；周视图左边让出刻度栏，七格正好对着下面的七列。
    private var dateStrip: some View {
        Group {
            switch mode {
            case .day:
                WeekStrip(day: $day, today: today)
            case .week:
                WeekStrip(day: $day, today: today, leading: AgendaWeekView.gutter, trailing: 4)
            }
        }
        .padding(.bottom, 4)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { monthTitle }
            .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Picker("视图", selection: Binding(get: { mode },
                                            set: { value in withAnimation(.snappy(duration: 0.3)) { modeRaw = value.rawValue } })) {
                ForEach(AgendaMode.allCases) { item in Text(item.label).tag(item) }
            }
            .pickerStyle(.segmented)
            .frame(width: 96)
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.smooth(duration: 0.35)) { day = today }
            } label: {
                TodayBadge(day: DayNumber.civil(today).day)
            }
            .accessibilityLabel("回到今天")
        }
    }

    private var monthTitle: some View {
        let date = DayNumber.civil(day)
        let currentYear = DayNumber.civil(today).year
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text("\(date.month)")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(date.month)))
            Text("月").font(.headline.weight(.bold))
            if date.year != currentYear {
                Text("\(String(date.year))年")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 4)
            }
        }
        .fixedSize()
        .animation(.snappy(duration: 0.3), value: date.month)
    }

    private var addButton: some View {
        Button {
            editorTarget = .new(on: DayNumber.key(day), reminders: store.document.reminders)
        } label: {
            Image(systemName: "plus")
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Palette.blue, in: Circle())
                .shadow(color: Palette.blue.opacity(0.3), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .padding(.trailing, 20)
        .padding(.bottom, 16)
        .accessibilityLabel("新建日程")
    }
}

/// 以前存过的 "month" 读出来是 nil，落回日视图。
enum AgendaMode: String, CaseIterable, Identifiable {
    case day, week
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: "日"
        case .week: "周"
        }
    }
}

/// 「今天」按钮上的小日历：顶上一道蓝（省心日历的主色），下面是今天几号。
struct TodayBadge: View {
    let day: Int

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.blue).frame(height: 5)
            Text("\(day)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxHeight: .infinity)
        }
        .frame(width: 20, height: 20)
        .background(Palette.inset)
        .clipShape(RoundedRectangle(cornerRadius: 4.5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.7), lineWidth: 1.4)
        }
        .foregroundStyle(.primary)
    }
}

// MARK: - 日视图

/// 一天一段，竖着一直往下排。滚到哪一天，顶上的日期条就选中哪一天。
private struct AgendaDayList: View {
    @Binding var day: Int
    let onEdit: (EventEditorTarget) -> Void

    @Environment(ScheduleStore.self) private var store
    @State private var position: Int?
    /// 点顶上日期跳过去时，滚动途中经过的日子不要反过来改选中。
    @State private var jumpTarget: Int?

    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }
    private var days: ClosedRange<Int> { (today - 365)...(today + 365) }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(days, id: \.self) { number in
                    AgendaDaySection(day: number, isToday: number == today, onEdit: onEdit)
                        .id(number)
                }
            }
            .scrollTargetLayout()
            .padding(.bottom, 90)
        }
        .scrollPosition(id: $position, anchor: .top)
        .onAppear { position = day }
        .onChange(of: position) { _, newValue in
            guard let newValue else { return }
            if let jumpTarget {
                if newValue == jumpTarget { self.jumpTarget = nil }
                return
            }
            if newValue != day { day = newValue }
        }
        .onChange(of: day) { _, newDay in
            guard newDay != position else { return }
            jumpTarget = newDay
            withAnimation(.smooth(duration: 0.4)) { position = newDay }
            // 保险：动画被打断没走到目标，也别一直卡着不同步
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                if jumpTarget == newDay { jumpTarget = nil }
            }
        }
    }
}

/// 日视图里的一天：日期标题（后面挂着当天班次的小徽章），一条条日程；今天还有一条「现在」红线。
/// 每条日程左滑露出删除。
private struct AgendaDaySection: View {
    let day: Int
    let isToday: Bool
    let onEdit: (EventEditorTarget) -> Void

    @Environment(ScheduleStore.self) private var store
    @Environment(\.showToast) private var showToast
    /// 哪一条日程正左滑开着。同一时间只开一条，滑开另一条时这条自动合上。
    @State private var openRow: String?

    private var key: String { DayNumber.key(day) }

    var body: some View {
        let document = store.document
        let occurrences = store.occurrences(on: key)
        let record = document.features.shiftsEnabled ? document.record(on: key) : nil
        let shift = record.flatMap { $0.planned ? document.shift($0.shiftId) : nil }

        VStack(alignment: .leading, spacing: 10) {
            header(shift: shift)

            if occurrences.isEmpty {
                Button {
                    onEdit(.new(on: key, reminders: document.reminders))
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                        Text("没有安排，点这里添加")
                    }
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 4)
                }
                .buttonStyle(.plain)
            } else {
                let nowIndex = isToday ? Self.nowIndex(occurrences) : nil
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occurrence in
                        if index == nowIndex { NowMarker() }
                        SwipeActionsRow(id: occurrence.id, openRow: $openRow,
                                        onEdit: { onEdit(.edit(occurrence)) },
                                        onDelete: { delete(occurrence) }) {
                            TimelineEntry(occurrence: occurrence,
                                          day: key,
                                          isLast: index == occurrences.count - 1,
                                          onOpen: { onEdit(.edit(occurrence)) },
                                          onToggle: {
                                              withAnimation(.snappy(duration: 0.25)) {
                                                  store.toggleCompletion(eventId: occurrence.event.id, on: occurrence.startKey)
                                              }
                                          })
                        }
                    }
                    if nowIndex == occurrences.count { NowMarker() }
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Palette.hairline.opacity(0.6)).frame(height: 0.5).padding(.leading, 18)
        }
    }

    /// 重复日程左滑删掉的只是这一次，单次日程整条删掉。
    private func delete(_ occurrence: EventOccurrence) {
        withAnimation(.snappy(duration: 0.28)) {
            if occurrence.event.recurrence.isRepeating {
                store.excludeOccurrence(eventId: occurrence.event.id, on: occurrence.startKey)
            } else {
                store.deleteEvent(id: occurrence.event.id)
            }
        }
        showToast(occurrence.event.recurrence.isRepeating ? "已删除这一次" : "已删除日程", symbol: "trash")
    }

    private func header(shift: ShiftDefinition?) -> some View {
        let date = DayNumber.civil(day)
        let weekday = ScheduleCalendar.weekdaySymbols[DayNumber.weekday(day)]
        let festival = Festivals.festival(on: key)
        return HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\(date.month)月\(date.day)日 周\(weekday)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(isToday ? AnyShapeStyle(Palette.red) : AnyShapeStyle(.primary))
            if isToday {
                Text("今天")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Palette.red, in: Capsule())
            }
            if let shift { ShiftBadge(shift: shift) }
            if let festival {
                Text(festival.name)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(festival.kind == .statutory ? Palette.holiday : Palette.traditionalFestival)
            }
            switch store.holidays.adjustment(on: key) {
            case .off: Text("休").font(.caption.weight(.bold)).foregroundStyle(Palette.holiday)
            case .work: Text("班").font(.caption.weight(.bold)).foregroundStyle(Palette.adjustedWorkday)
            case nil: EmptyView()
            }
            Spacer(minLength: 0)
            Text("农历" + LunarCalendar.fullText(for: key))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    /// 「现在」红线插在第几条前面：全天的排在最前面不算，定时的按开始时间比。
    static func nowIndex(_ occurrences: [EventOccurrence]) -> Int {
        let parts = ScheduleCalendar.calendar.dateComponents([.hour, .minute], from: Date())
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        for (index, occurrence) in occurrences.enumerated() where !occurrence.event.isAllDay {
            if (EventClock.minutes(occurrence.event.startTime) ?? 0) > now { return index }
        }
        return occurrences.count
    }
}

/// 日视图里「现在」那条红线。
private struct NowMarker: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            HStack(spacing: 6) {
                Text(EventClock.split(context.date).time)
                    .font(.system(size: 11, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(Palette.red, in: Capsule())
                Rectangle().fill(Palette.red).frame(height: 1.5)
            }
        }
        .padding(.vertical, 6)
        .accessibilityLabel("现在")
    }
}

/// 当天的班次：日期标题后面的一枚小徽章（色点 + 班次名），当标题的一部分看，
/// 不和日程排成一样的条目，一天天往下翻不显得乱。
private struct ShiftBadge: View {
    let shift: ShiftDefinition

    var body: some View {
        HStack(spacing: 4) {
            Text(shift.shortName)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(shift.inkOnTint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(minWidth: 15)
                .frame(height: 15)
                .padding(.horizontal, shift.shortName.count > 1 ? 2 : 0)
                .background(shift.tint, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            Text(shift.name)
                .font(.caption.weight(.semibold))
                .foregroundStyle(shift.tint)
                .lineLimit(1)
        }
        .padding(.leading, 2)
        .padding(.trailing, 7)
        .padding(.vertical, 2)
        .background(shift.tint.opacity(0.12), in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(shift.fullRange.isEmpty ? shift.name : "\(shift.name)，\(shift.fullRange)")
    }
}

/// 时间线上的一条事项：左边一颗带图标的彩色胶囊（越长的日程胶囊越高），
/// 中间时间和标题，右边一个完成圈。
struct TimelineEntry: View {
    let occurrence: EventOccurrence
    let day: String
    var isLast: Bool = false
    let onOpen: () -> Void
    let onToggle: () -> Void

    var body: some View {
        let event = occurrence.event
        let tone = Tone.event(event.color)
        let done = occurrence.isCompleted
        // 只有左边的图标胶囊和时间能点开编辑；标题、空白处不响应点按。
        // 之前整行都是一个大按钮，上下滑、左滑删除时手指一松就会弹出编辑抽屉。
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                Image(systemName: event.symbol ?? EventSymbols.fallback)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: capsuleHeight)
                    .background(tone.solid.opacity(done ? 0.45 : 1), in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("编辑「\(event.title)」")
            VStack(alignment: .leading, spacing: 2) {
                Button(action: onOpen) {
                    Text(timeText)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
                Text(event.title)
                    .font(.headline)
                    .strikethrough(done, color: .secondary)
                    .foregroundStyle(done ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
                    .lineLimit(2)
                if let location = event.location {
                    Label(location, systemImage: "mappin")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)

            Button(action: onToggle) {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(tone.solid)
                    .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(done ? "标记为未完成" : "标记为完成")
            .sensoryFeedback(.success, trigger: done) { _, new in new }
        }
        .padding(.vertical, 5)
        // 胶囊之间的连线
        .background(alignment: .topLeading) {
            if !isLast {
                Rectangle()
                    .fill(Palette.hairline)
                    .frame(width: 2)
                    .padding(.top, capsuleHeight / 2 + 5)
                    .padding(.bottom, -capsuleHeight / 2 - 5)
                    .offset(x: 23)
            }
        }
    }

    private var durationMinutes: Int? {
        let event = occurrence.event
        guard !event.isAllDay, !occurrence.isMultiDay,
              let start = EventClock.minutes(event.startTime), let end = EventClock.minutes(event.endTime)
        else { return nil }
        return max(0, end - start)
    }

    /// 一小时以内是圆，越长越高，封顶 110pt。
    private var capsuleHeight: CGFloat {
        guard let minutes = durationMinutes else { return 48 }
        return min(110, max(48, CGFloat(minutes) * 0.8))
    }

    private var timeText: String {
        let event = occurrence.event
        if occurrence.isMultiDay, let current = DayNumber.of(day) {
            let index = current - occurrence.start + 1
            let total = occurrence.end - occurrence.start + 1
            return "\(event.isAllDay ? "全天" : event.timeLabel) · 第 \(index)/\(total) 天"
        }
        if event.isAllDay { return "全天" }
        guard let minutes = durationMinutes else { return event.timeLabel }
        let length = minutes >= 60 && minutes % 60 == 0 ? "\(minutes / 60) 小时" : "\(minutes) 分钟"
        return "\(event.startTime) – \(event.endTime)（\(length)）"
    }
}

// MARK: - 周视图

/// 周视图：顶栏下面只有本周一行日期（周一到周日，和日视图同一条日期条），
/// 下面七列共用一条时间轴，像一张周历。
///
/// 左边刻度写全「08:00」，和日历页当天时间轴一个样子；今天在这一周里时，
/// 刻度栏里有一颗红色「现在」胶囊写着几点几分，红线横过整周、今天那一列加粗。
/// 全天日程放在时间轴最上面，跟着一起滚，不再多占一行表头。
/// 左右滑动换周，竖着滚到哪个钟点，换周后还停在那里。
private struct AgendaWeekView: View {
    @Binding var day: Int
    let onEdit: (EventEditorTarget) -> Void

    @Environment(ScheduleStore.self) private var store
    /// 翻周的方向，给切换动画用：往后翻从右边推进来，往前翻从左边。
    @State private var forward = true

    static let hourHeight: CGFloat = 44
    /// 刻度栏：放得下「08:00」和「现在」胶囊，胶囊左边也不贴屏幕边。
    static let gutter: CGFloat = 54
    /// 时间轴上下各留一点，0 点和 24 点的刻度字不被切掉。
    static let gridInset: CGFloat = 10

    private var weekStart: Int { day - DayNumber.weekday(day) }
    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }

    var body: some View {
        let days = (0..<7).map { weekStart + $0 }
        let perDay = days.map { store.occurrences(on: DayNumber.key($0)) }

        VStack(spacing: 0) {
            // 本周那一排日期在顶栏里（AgendaScreen 的 dateStrip），这里只有时间轴
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        allDayBand(days: days, perDay: perDay)
                        WeekTimeGrid(days: days, perDay: perDay, today: today, onEdit: onEdit)
                            .overlay(alignment: .topLeading) {
                                // 滚动定位用的锚点，一小时一个，和时间轴同一套坐标
                                VStack(spacing: 0) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Color.clear.frame(height: Self.hourHeight).id(hour)
                                    }
                                }
                                .padding(.top, Self.gridInset)
                                .allowsHitTesting(false)
                            }
                    }
                    .id(weekStart)
                    .transition(slide)
                    .padding(.bottom, 90)
                }
                .onAppear {
                    let hour = Calendar.current.component(.hour, from: Date())
                    proxy.scrollTo(max(0, min(hour - 1, 16)), anchor: .top)
                }
            }
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 24)
                .onEnded { value in
                    let dx = value.translation.width, dy = value.translation.height
                    guard abs(dx) > 60, abs(dx) > abs(dy) * 1.5 else { return }
                    step(dx < 0 ? 1 : -1)
                }
        )
        .sensoryFeedback(.selection, trigger: weekStart)
    }

    private var slide: AnyTransition {
        .asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity))
    }

    private func step(_ weeks: Int) {
        forward = weeks > 0
        withAnimation(.spring(duration: 0.3, bounce: 0)) { day += 7 * weeks }
    }

    /// 全天日程：时间轴最上面一条，跟着一起滚。没有全天日程就不占地方。
    @ViewBuilder
    private func allDayBand(days: [Int], perDay: [[EventOccurrence]]) -> some View {
        let allDay = perDay.map { $0.filter { $0.event.isAllDay } }
        if allDay.contains(where: { !$0.isEmpty }) {
            HStack(alignment: .top, spacing: 0) {
                Text("全天")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(width: Self.gutter - 6, alignment: .trailing)
                    .padding(.trailing, 6)
                    .padding(.top, 2)
                ForEach(Array(allDay.enumerated()), id: \.offset) { _, items in
                    VStack(spacing: 2) {
                        ForEach(items.prefix(2)) { occurrence in
                            let tone = Tone.event(occurrence.event.color)
                            Button { onEdit(.edit(occurrence)) } label: {
                                Text(occurrence.event.title)
                                    .font(.system(size: 9, weight: .semibold))
                                    .strikethrough(occurrence.isCompleted, color: tone.ink)
                                    .foregroundStyle(tone.ink)
                                    .lineLimit(1)
                                    .padding(.horizontal, 2)
                                    .frame(maxWidth: .infinity, minHeight: 16)
                                    .background(tone.fill, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        if items.count > 2 {
                            Text("+\(items.count - 2)").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.horizontal, 1)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.trailing, 4)
            .padding(.top, 6)
        }
    }
}

/// 一周的时间格子。刻度线、刻度字、色块、「现在」红线全在同一个坐标系里摆，
/// 分钟换算成 y 只有一个公式，刻度和色块不会对不齐。
private struct WeekTimeGrid: View {
    let days: [Int]
    let perDay: [[EventOccurrence]]
    let today: Int
    let onEdit: (EventEditorTarget) -> Void

    private var hourHeight: CGFloat { AgendaWeekView.hourHeight }
    private var gutter: CGFloat { AgendaWeekView.gutter }
    private var inset: CGFloat { AgendaWeekView.gridInset }

    private func y(_ minutes: Int) -> CGFloat { inset + CGFloat(minutes) / 60 * hourHeight }

    var body: some View {
        GeometryReader { geometry in
            let gridWidth = geometry.size.width - gutter - 4
            let columnWidth = gridWidth / 7
            let todayColumn = days.firstIndex(of: today)
            ZStack(alignment: .topLeading) {
                // 今天那一列淡底
                if let index = todayColumn {
                    Rectangle()
                        .fill(Palette.todayFill.opacity(0.55))
                        .frame(width: columnWidth, height: hourHeight * 24)
                        .offset(x: gutter + CGFloat(index) * columnWidth, y: inset)
                }
                // 刻度线与刻度字（写全到分钟）；「现在」胶囊附近的刻度让出来
                ForEach(0...24, id: \.self) { hour in
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: gridWidth, height: 0.5)
                        .offset(x: gutter, y: y(hour * 60))
                    Text(String(format: "%02d:00", hour))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter - 6, height: 14, alignment: .trailing)
                        .offset(y: y(hour * 60) - 7)
                        .opacity(todayColumn != nil && Self.nearNow(hour) ? 0 : 1)
                }
                // 列分隔线
                ForEach(1..<7, id: \.self) { index in
                    Rectangle()
                        .fill(Palette.hairline.opacity(0.6))
                        .frame(width: 0.5, height: hourHeight * 24)
                        .offset(x: gutter + CGFloat(index) * columnWidth, y: inset)
                }
                // 日程色块
                ForEach(Array(days.enumerated()), id: \.offset) { index, number in
                    let timed = perDay[index].filter { !$0.event.isAllDay }
                    ForEach(TimelineLayout.place(timed, day: number), id: \.occurrence.id) { item in
                        block(item, columnWidth: columnWidth, column: index)
                    }
                }
                // 现在
                if let index = todayColumn {
                    nowLine(gridWidth: gridWidth, columnWidth: columnWidth, column: index)
                }
            }
        }
        .frame(height: hourHeight * 24 + inset * 2)
    }

    /// 离现在不到 15 分钟的整点刻度字让给「现在」胶囊。
    private static func nearNow(_ hour: Int) -> Bool {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let now = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
        return abs(now - hour * 60) < 15
    }

    /// 刻度栏里一颗红胶囊写着「14:05」，一条细红线横过整周，今天那一列加粗。
    private func nowLine(gridWidth: CGFloat, columnWidth: CGFloat, column: Int) -> some View {
        TimelineView(.everyMinute) { context in
            let parts = Calendar.current.dateComponents([.hour, .minute], from: context.date)
            let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(Palette.red.opacity(0.35))
                    .frame(width: gridWidth, height: 1)
                    .offset(x: gutter, y: y(minutes) - 0.5)
                Rectangle()
                    .fill(Palette.red)
                    .frame(width: columnWidth, height: 2)
                    .offset(x: gutter + CGFloat(column) * columnWidth, y: y(minutes) - 1)
                Text(EventClock.text(minutes))
                    .font(.system(size: 10.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(Palette.red, in: Capsule())
                    .fixedSize()
                    .frame(width: gutter - 2, alignment: .trailing)
                    .offset(y: y(minutes) - 8.5)
            }
        }
        .allowsHitTesting(false)
        .accessibilityLabel("现在")
    }

    private func block(_ item: TimelineLayout.Placed, columnWidth: CGFloat, column: Int) -> some View {
        let tone = Tone.event(item.occurrence.event.color)
        let done = item.occurrence.isCompleted
        let width = columnWidth / CGFloat(item.columns)
        let height = max(16, CGFloat(item.end - item.start) / 60 * hourHeight - 1)
        return Button { onEdit(.edit(item.occurrence)) } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.occurrence.event.title)
                    .font(.system(size: 9.5, weight: .semibold))
                    .strikethrough(done, color: tone.ink)
                    .lineLimit(height > 30 ? 3 : 1)
                if height > 44 {
                    Text(item.occurrence.event.startTime)
                        .font(.system(size: 8.5))
                        .monospacedDigit()
                        .opacity(0.8)
                }
            }
            .foregroundStyle(tone.ink.opacity(done ? 0.55 : 1))
            .padding(.horizontal, 3)
            .padding(.vertical, 2)
            .frame(width: max(8, width - 2), height: height, alignment: .topLeading)
            .background(tone.fill.opacity(done ? 0.5 : 1))
            .overlay(alignment: .leading) { Rectangle().fill(tone.solid).frame(width: 2) }
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .offset(x: gutter + CGFloat(column) * columnWidth + CGFloat(item.column) * width + 1,
                y: y(item.start))
    }
}
