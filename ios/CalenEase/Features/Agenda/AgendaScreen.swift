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
    @Environment(ScheduleStore.self) private var store

    @AppStorage("agenda.mode") private var modeRaw = AgendaMode.day.rawValue
    @State private var day: Int = DayNumber.of(ScheduleCalendar.todayKey) ?? 0
    @State private var editorTarget: EventEditorTarget?
    /// 内容有没有滚到顶栏底下，决定顶栏下沿画不画渐变。
    @State private var isScrolled = false

    private var mode: AgendaMode { AgendaMode(rawValue: modeRaw) ?? .day }
    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .day:
                    AgendaDayList(day: $day, isScrolled: $isScrolled, onEdit: open)
                case .week:
                    AgendaWeekView(day: $day, isScrolled: $isScrolled, onEdit: open)
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { pinnedBar }
            .background(Palette.canvas)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) { addButton }
            .sheet(item: $editorTarget) { target in
                EventEditorSheet(target: target)
            }
        }
    }

    private func open(_ target: EventEditorTarget) { editorTarget = target }

    // MARK: - 顶栏

    private var pinnedBar: some View {
        VStack(spacing: 8) {
            header
                .padding(.horizontal, 18)
                .padding(.top, 4)
            if mode == .day {
                WeekStrip(day: $day, today: today)
            }
        }
        .padding(.bottom, 6)
        .background { PinnedBarBackground(showsFade: isScrolled) }
    }

    private var header: some View {
        let date = DayNumber.civil(day)
        let currentYear = DayNumber.civil(today).year
        return HStack(alignment: .center, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(date.month)")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: Double(date.month)))
                Text("月").font(.title3.weight(.bold))
                if date.year != currentYear {
                    Text("\(String(date.year))年")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 4)
                }
            }
            .animation(.snappy(duration: 0.3), value: date.month)

            Spacer(minLength: 0)

            Picker("视图", selection: Binding(get: { mode },
                                            set: { value in withAnimation(.snappy(duration: 0.3)) { modeRaw = value.rawValue } })) {
                ForEach(AgendaMode.allCases) { item in Text(item.label).tag(item) }
            }
            .pickerStyle(.segmented)
            .frame(width: 96)

            Button {
                withAnimation(.smooth(duration: 0.35)) { day = today }
            } label: {
                TodayBadge(day: DayNumber.civil(today).day)
                    .frame(width: 38, height: 38)
                    .background(Palette.card, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("回到今天")
        }
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

/// 「今天」按钮上的小日历：顶上一道红，下面是今天几号。
struct TodayBadge: View {
    let day: Int

    var body: some View {
        VStack(spacing: 0) {
            Rectangle().fill(Palette.red).frame(height: 5)
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

// MARK: - 一周的日期条

/// 日视图顶上的一周日期。左右翻周；每天底下几个小圆点是当天日程的颜色。
private struct WeekStrip: View {
    @Binding var day: Int
    let today: Int

    @Environment(ScheduleStore.self) private var store
    @State private var weekPosition: Int?

    private static func weekStart(_ day: Int) -> Int { day - DayNumber.weekday(day) }
    private var weeks: [Int] {
        let anchor = Self.weekStart(today)
        return stride(from: anchor - 7 * 104, through: anchor + 7 * 104, by: 7).map { $0 }
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(weeks, id: \.self) { start in
                    HStack(spacing: 0) {
                        ForEach(0..<7, id: \.self) { offset in
                            cell(start + offset)
                        }
                    }
                    .padding(.horizontal, 8)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $weekPosition)
        .frame(height: 66)
        .onAppear { weekPosition = Self.weekStart(day) }
        .onChange(of: day) { _, newDay in
            let start = Self.weekStart(newDay)
            guard weekPosition != start else { return }
            withAnimation(.smooth(duration: 0.3)) { weekPosition = start }
        }
        .onChange(of: weekPosition) { _, start in
            // 手指翻到别的一周：选中那一周里同一个星期几
            guard let start, Self.weekStart(day) != start else { return }
            day = start + DayNumber.weekday(day)
        }
    }

    private func cell(_ number: Int) -> some View {
        let date = DayNumber.civil(number)
        let isSelected = number == day
        let isToday = number == today
        let colors = Array(Set(store.occurrences(on: DayNumber.key(number)).map(\.event.color))).sorted().prefix(3)
        return Button {
            withAnimation(.smooth(duration: 0.35)) { day = number }
        } label: {
            VStack(spacing: 4) {
                Text(ScheduleCalendar.weekdaySymbols[DayNumber.weekday(number)])
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(date.day)")
                    .font(.system(size: 17, weight: isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                                     : isToday ? AnyShapeStyle(Palette.red) : AnyShapeStyle(.primary))
                    .frame(width: 34, height: 34)
                    .background {
                        if isSelected { Circle().fill(isToday ? Palette.red : Palette.blue) }
                    }
                HStack(spacing: 2) {
                    ForEach(Array(colors), id: \.self) { hex in
                        Circle().fill(Tone.event(hex).solid).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.month)月\(date.day)日")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - 日视图

/// 一天一段，竖着一直往下排。滚到哪一天，顶上的日期条就选中哪一天。
private struct AgendaDayList: View {
    @Binding var day: Int
    @Binding var isScrolled: Bool
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
        .onScrollGeometryChange(for: Bool.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top > 1
        } action: { _, scrolled in
            withAnimation(.easeOut(duration: 0.18)) { isScrolled = scrolled }
        }
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
                        SwipeToDelete(id: occurrence.id, openRow: $openRow, onDelete: { delete(occurrence) }) {
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

/// 左滑露出一颗红色删除按钮；滑过一大半直接删。只认横向拖动，竖着滑照常滚动列表。
struct SwipeToDelete<Content: View>: View {
    let id: String
    @Binding var openRow: String?
    let onDelete: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var dragging = false
    private let buttonWidth: CGFloat = 76

    var body: some View {
        content()
            .offset(x: offset)
            .background(alignment: .trailing) {
                Button(role: .destructive) {
                    close()
                    onDelete()
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: "trash.fill").font(.system(size: 16, weight: .semibold))
                        Text("删除").font(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(width: max(0, -offset - 8))
                    .frame(maxHeight: .infinity)
                    .background(Palette.red, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.vertical, 4)
                    .opacity(offset < -12 ? 1 : 0)
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
            // 只裁左右：时间线上胶囊之间的连线要伸到下一条，上下不能裁
            .mask { Rectangle().padding(.vertical, -400) }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        let dx = value.translation.width, dy = value.translation.height
                        guard dragging || abs(dx) > abs(dy) * 1.4 else { return }
                        if !dragging {
                            dragging = true
                            startOffset = offset
                            if openRow != id { openRow = id }
                        }
                        offset = min(0, startOffset + dx)
                    }
                    .onEnded { value in
                        guard dragging else { return }
                        dragging = false
                        let predicted = value.predictedEndTranslation.width
                        withAnimation(.snappy(duration: 0.25)) {
                            if offset < -220 || predicted < -380 {
                                offset = -600
                            } else if offset < -buttonWidth / 2 || predicted < -120 {
                                offset = -buttonWidth
                                openRow = id
                            } else {
                                close()
                            }
                        }
                        if offset <= -600 {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                onDelete()
                                offset = 0
                                if openRow == id { openRow = nil }
                            }
                        }
                    }
            )
            .onChange(of: openRow) { _, row in
                if row != id, offset != 0 { withAnimation(.snappy(duration: 0.22)) { offset = 0 } }
            }
            .accessibilityAction(named: "删除") { onDelete() }
    }

    private func close() {
        offset = 0
        if openRow == id { openRow = nil }
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
        HStack(alignment: .center, spacing: 12) {
            Button(action: onOpen) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: event.symbol ?? EventSymbols.fallback)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 48, height: capsuleHeight)
                        .background(tone.solid.opacity(done ? 0.45 : 1), in: Capsule())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(timeText)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
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
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

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

/// 周视图：周一到周日七列，共用同一条竖着的时间轴。
///
/// 原来是横向分页、每一页各带一个竖向滚动：翻页时新的一周总从 7 点开始，旧的一周停在别处，
/// 刻度和色块在手指底下错开；日期表头也占了很大一块。现在只有一个竖向滚动，
/// 左右滑动只换这一周的内容，时间停在哪就还在哪；表头压成一行「一 22」。
private struct AgendaWeekView: View {
    @Binding var day: Int
    @Binding var isScrolled: Bool
    let onEdit: (EventEditorTarget) -> Void

    @Environment(ScheduleStore.self) private var store
    /// 翻周的方向，给切换动画用：往后翻从右边推进来，往前翻从左边。
    @State private var forward = true

    static let hourHeight: CGFloat = 40
    static let gutter: CGFloat = 34
    /// 时间轴上下各留一点，0 点和 24 点的刻度字不被切掉。
    static let gridInset: CGFloat = 8

    private var weekStart: Int { day - DayNumber.weekday(day) }
    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }

    var body: some View {
        let days = (0..<7).map { weekStart + $0 }
        let perDay = days.map { store.occurrences(on: DayNumber.key($0)) }
        let allDay = perDay.map { $0.filter { $0.event.isAllDay } }

        VStack(spacing: 0) {
            Group {
                header(days)
                if allDay.contains(where: { !$0.isEmpty }) {
                    allDayRow(allDay)
                }
            }
            .id(weekStart)
            .transition(slide)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    WeekTimeGrid(days: days, perDay: perDay, today: today, onEdit: onEdit)
                        .id(weekStart)
                        .transition(slide)
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
                        .padding(.bottom, 90)
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    geometry.contentOffset.y + geometry.contentInsets.top > 1
                } action: { _, scrolled in
                    withAnimation(.easeOut(duration: 0.18)) { isScrolled = scrolled }
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
        withAnimation(.snappy(duration: 0.3)) { day += 7 * weeks }
    }

    /// 一行：星期 + 日期。选中的那天蓝底，今天红字（选中又是今天就红底）。
    private func header(_ days: [Int]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: Self.gutter)
            ForEach(days, id: \.self) { number in
                let date = DayNumber.civil(number)
                let isSelected = number == day
                let isToday = number == today
                Button {
                    withAnimation(.snappy(duration: 0.2)) { day = number }
                } label: {
                    HStack(spacing: 2) {
                        Text(ScheduleCalendar.weekdaySymbols[DayNumber.weekday(number)])
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.85)) : AnyShapeStyle(.secondary))
                        Text("\(date.day)")
                            .font(.system(size: 13, weight: isSelected || isToday ? .bold : .medium))
                            .monospacedDigit()
                            .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                                             : isToday ? AnyShapeStyle(Palette.red) : AnyShapeStyle(.primary))
                    }
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
                    .background {
                        if isSelected {
                            Capsule().fill(isToday ? Palette.red : Palette.blue).padding(.horizontal, 2)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(date.month)月\(date.day)日 周\(ScheduleCalendar.weekdaySymbols[DayNumber.weekday(number)])")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
    }

    private func allDayRow(_ allDay: [[EventOccurrence]]) -> some View {
        HStack(alignment: .top, spacing: 0) {
            Text("全天")
                .font(.system(size: 9.5))
                .foregroundStyle(.tertiary)
                .frame(width: Self.gutter)
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
        .padding(.horizontal, 4)
        .padding(.bottom, 4)
    }
}

/// 一周的时间格子。刻度线、刻度字、色块、「现在」红线全在同一个坐标系里摆，
/// 分钟换算成 y 只有一个公式，不会一个跟着行高走、一个跟着偏移走而对不齐。
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
            let columnWidth = (geometry.size.width - gutter - 4) / 7
            ZStack(alignment: .topLeading) {
                // 今天那一列淡底
                if let index = days.firstIndex(of: today) {
                    Rectangle()
                        .fill(Palette.todayFill.opacity(0.55))
                        .frame(width: columnWidth, height: hourHeight * 24)
                        .offset(x: gutter + CGFloat(index) * columnWidth, y: inset)
                }
                // 刻度线与刻度字
                ForEach(0...24, id: \.self) { hour in
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(width: geometry.size.width - gutter - 4, height: 0.5)
                        .offset(x: gutter, y: y(hour * 60))
                    Text(String(format: "%02d", hour))
                        .font(.system(size: 9.5))
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: gutter - 6, height: 12, alignment: .trailing)
                        .offset(y: y(hour * 60) - 6)
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
                if let index = days.firstIndex(of: today) {
                    TimelineView(.everyMinute) { context in
                        let parts = Calendar.current.dateComponents([.hour, .minute], from: context.date)
                        let minutes = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
                        HStack(spacing: 0) {
                            Circle().fill(Palette.red).frame(width: 7, height: 7)
                            Rectangle().fill(Palette.red).frame(height: 1.5)
                        }
                        .frame(width: columnWidth + 3.5)
                        .offset(x: gutter + CGFloat(index) * columnWidth - 3.5, y: y(minutes) - 3.5)
                    }
                    .allowsHitTesting(false)
                }
            }
        }
        .frame(height: hourHeight * 24 + inset * 2)
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
                if height > 44, !item.occurrence.event.isAllDay {
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
