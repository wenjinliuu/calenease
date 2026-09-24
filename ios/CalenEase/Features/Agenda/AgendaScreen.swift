import SwiftUI

/// 事项页：所有日程按日、周、月三种方式看，有点像 Outlook 的日历。
///
/// - 日：顶上一排一周的日期，下面一天一段竖着往下排，上下滑时顶上的日期跟着走；
///   点顶上的日期，下面滑到那一天。今天那一段里有一条「现在」的红线。
/// - 周：一周七列的时间格子，左右翻周。
/// - 月：月历（只画日程条）+ 选中那天的事项列表。
///
/// 三种视图共用同一个「选中的日子」，切来切去停在同一天。
struct AgendaScreen: View {
    @Environment(ScheduleStore.self) private var store

    @AppStorage("agenda.mode") private var modeRaw = AgendaMode.day.rawValue
    @State private var day: Int = DayNumber.of(ScheduleCalendar.todayKey) ?? 0
    @State private var editorTarget: EventEditorTarget?
    @State private var timelineDay: DateKeyBox?

    private var mode: AgendaMode { AgendaMode(rawValue: modeRaw) ?? .day }
    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .day:
                    AgendaDayList(day: $day, onEdit: open)
                case .week:
                    AgendaWeekView(day: $day, onEdit: open)
                case .month:
                    AgendaMonthView(day: $day, onEdit: open,
                                    onOpenDay: { timelineDay = DateKeyBox(key: DayNumber.key($0)) })
                }
            }
            .safeAreaInset(edge: .top, spacing: 0) { pinnedBar }
            .background(Palette.canvas)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .overlay(alignment: .bottomTrailing) { addButton }
            .sheet(item: $editorTarget) { target in
                EventEditorSheet(target: target)
            }
            .sheet(item: $timelineDay) { box in
                DayTimelineSheet(startDate: box.key)
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
        .background { PinnedBarBackground() }
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
            .frame(width: 132)

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

enum AgendaMode: String, CaseIterable, Identifiable {
    case day, week, month
    var id: String { rawValue }
    var label: String {
        switch self {
        case .day: "日"
        case .week: "周"
        case .month: "月"
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

/// 日视图里的一天：日期标题，班次，一条条日程；今天还有一条「现在」红线。
private struct AgendaDaySection: View {
    let day: Int
    let isToday: Bool
    let onEdit: (EventEditorTarget) -> Void

    @Environment(ScheduleStore.self) private var store

    private var key: String { DayNumber.key(day) }

    var body: some View {
        let document = store.document
        let occurrences = store.occurrences(on: key)
        let record = document.features.shiftsEnabled ? document.record(on: key) : nil
        let shift = record.flatMap { $0.planned ? document.shift($0.shiftId) : nil }

        VStack(alignment: .leading, spacing: 10) {
            header

            if let shift {
                ShiftEntry(shift: shift)
            }

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

    private var header: some View {
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

/// 当天的班次，排在日程前面。
private struct ShiftEntry: View {
    let shift: ShiftDefinition

    var body: some View {
        HStack(spacing: 12) {
            ShiftOrb(shift: shift, size: 30)
                .frame(width: 48)
            VStack(alignment: .leading, spacing: 1) {
                Text(shift.name).font(.subheadline.weight(.semibold))
                if !shift.fullRange.isEmpty {
                    Text(shift.fullRange)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
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

/// 一周七列的时间格子，左右翻周。
private struct AgendaWeekView: View {
    @Binding var day: Int
    let onEdit: (EventEditorTarget) -> Void

    @Environment(ScheduleStore.self) private var store
    @State private var position: Int?

    private static func weekStart(_ day: Int) -> Int { day - DayNumber.weekday(day) }
    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }
    private var weeks: [Int] {
        let anchor = Self.weekStart(today)
        return stride(from: anchor - 7 * 104, through: anchor + 7 * 104, by: 7).map { $0 }
    }

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(weeks, id: \.self) { start in
                    WeekGridPage(weekStart: start, selected: day, today: today, onEdit: onEdit,
                                 onSelect: { day = $0 })
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .onAppear { position = Self.weekStart(day) }
        .onChange(of: position) { _, start in
            guard let start, Self.weekStart(day) != start else { return }
            day = start + DayNumber.weekday(day)
        }
        .onChange(of: day) { _, newDay in
            let start = Self.weekStart(newDay)
            guard position != start else { return }
            withAnimation(.smooth(duration: 0.35)) { position = start }
        }
    }
}

private struct WeekGridPage: View {
    let weekStart: Int
    let selected: Int
    let today: Int
    let onEdit: (EventEditorTarget) -> Void
    let onSelect: (Int) -> Void

    @Environment(ScheduleStore.self) private var store

    private static let hourHeight: CGFloat = 44
    private static let gutter: CGFloat = 38

    var body: some View {
        let days = (0..<7).map { weekStart + $0 }
        let perDay = days.map { store.occurrences(on: DayNumber.key($0)) }
        let allDay = perDay.map { $0.filter { $0.event.isAllDay } }

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Color.clear.frame(width: Self.gutter)
                ForEach(days, id: \.self) { number in
                    dayHeader(number)
                }
            }
            .padding(.bottom, 4)

            if allDay.contains(where: { !$0.isEmpty }) {
                HStack(alignment: .top, spacing: 0) {
                    Text("全天")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.gutter)
                    ForEach(Array(allDay.enumerated()), id: \.offset) { index, items in
                        VStack(spacing: 2) {
                            ForEach(items.prefix(2)) { occurrence in
                                let tone = Tone.event(occurrence.event.color)
                                Button { onEdit(.edit(occurrence)) } label: {
                                    Text(occurrence.event.title)
                                        .font(.system(size: 9, weight: .semibold))
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
                .padding(.bottom, 4)
            }
            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        VStack(spacing: 0) {
                            ForEach(0..<24, id: \.self) { hour in
                                HStack(alignment: .top, spacing: 0) {
                                    Text(String(format: "%02d", hour))
                                        .font(.caption2)
                                        .monospacedDigit()
                                        .foregroundStyle(.tertiary)
                                        .frame(width: Self.gutter - 4, alignment: .trailing)
                                        .padding(.trailing, 4)
                                        .offset(y: -6)
                                    Rectangle().fill(Palette.hairline).frame(height: 0.5)
                                }
                                .frame(height: Self.hourHeight, alignment: .top)
                                .id(hour)
                            }
                        }
                        GeometryReader { geometry in
                            let columnWidth = (geometry.size.width - Self.gutter) / 7
                            ForEach(Array(days.enumerated()), id: \.offset) { index, number in
                                if number == today {
                                    Rectangle()
                                        .fill(Palette.todayFill.opacity(0.5))
                                        .frame(width: columnWidth, height: Self.hourHeight * 24)
                                        .offset(x: Self.gutter + CGFloat(index) * columnWidth)
                                        .allowsHitTesting(false)
                                }
                                let timed = perDay[index].filter { !$0.event.isAllDay }
                                ForEach(TimelineLayout.place(timed, day: number), id: \.occurrence.id) { item in
                                    block(item, columnWidth: columnWidth, column: index)
                                }
                            }
                        }
                        .frame(height: Self.hourHeight * 24)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 90)
                }
                .onAppear { proxy.scrollTo(7, anchor: .top) }
            }
        }
    }

    private func dayHeader(_ number: Int) -> some View {
        let date = DayNumber.civil(number)
        let isSelected = number == selected
        let isToday = number == today
        return Button { onSelect(number) } label: {
            VStack(spacing: 2) {
                Text(ScheduleCalendar.weekdaySymbols[DayNumber.weekday(number)])
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                Text("\(date.day)")
                    .font(.system(size: 15, weight: isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                                     : isToday ? AnyShapeStyle(Palette.red) : AnyShapeStyle(.primary))
                    .frame(width: 28, height: 28)
                    .background {
                        if isSelected { Circle().fill(isToday ? Palette.red : Palette.blue) }
                    }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func block(_ item: TimelineLayout.Placed, columnWidth: CGFloat, column: Int) -> some View {
        let tone = Tone.event(item.occurrence.event.color)
        let width = columnWidth / CGFloat(item.columns)
        let height = max(18, CGFloat(item.end - item.start) / 60 * Self.hourHeight - 1)
        return Button { onEdit(.edit(item.occurrence)) } label: {
            Text(item.occurrence.event.title)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(tone.ink)
                .lineLimit(height > 30 ? 3 : 1)
                .padding(3)
                .frame(width: max(8, width - 2), height: height, alignment: .topLeading)
                .background(tone.fill)
                .overlay(alignment: .leading) { Rectangle().fill(tone.solid).frame(width: 2) }
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
        .buttonStyle(.plain)
        .offset(x: Self.gutter + CGFloat(column) * columnWidth + CGFloat(item.column) * width + 1,
                y: CGFloat(item.start) / 60 * Self.hourHeight)
    }
}

// MARK: - 月视图

/// 月历（只画日程条）+ 选中那天的事项。点一下选中，再点一下打开那天的时间轴。
private struct AgendaMonthView: View {
    @Binding var day: Int
    let onEdit: (EventEditorTarget) -> Void
    let onOpenDay: (Int) -> Void

    @Environment(ScheduleStore.self) private var store
    @State private var position: Int?

    private static func monthIndex(_ day: Int) -> Int {
        let date = DayNumber.civil(day)
        return date.year * 12 + date.month - 1
    }

    private var today: Int { DayNumber.of(store.todayKey) ?? 0 }
    private var range: ClosedRange<Int> {
        let current = Self.monthIndex(today)
        return (current - 60)...(current + 60)
    }

    /// 月视图里的月历不画班次那两行，每格放三条日程。
    private var agendaDocument: ScheduleDocument {
        var copy = store.document
        copy.features.shiftsEnabled = false
        copy.display.eventSlots = 3
        return copy
    }

    var body: some View {
        let document = agendaDocument
        let layout = CellLayout(document: document)
        let gridHeight = CalendarMonthGrid.height(rows: 6, layout: layout)
        let selectedKey = DayNumber.key(day)
        let occurrences = store.occurrences(on: selectedKey)

        ScrollView {
            VStack(spacing: 14) {
                ScrollView(.horizontal) {
                    LazyHStack(alignment: .top, spacing: 0) {
                        ForEach(range, id: \.self) { index in
                            let monthKey = ScheduleCalendar.monthKey(year: index / 12, month: index % 12)
                            CalendarMonthGrid(year: index / 12,
                                              month: index % 12,
                                              document: document,
                                              todayKey: store.todayKey,
                                              holidays: store.holidays,
                                              selectedDay: selectedKey.hasPrefix(monthKey) ? selectedKey : nil,
                                              onSelect: { key in
                                                  guard let number = DayNumber.of(key) else { return }
                                                  if number == day {
                                                      onOpenDay(number)
                                                  } else {
                                                      withAnimation(.snappy(duration: 0.2)) { day = number }
                                                  }
                                              })
                                .equatable()
                                .frame(height: gridHeight, alignment: .top)
                                .padding(.horizontal, 6)
                                .containerRelativeFrame(.horizontal)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $position)
                .frame(height: gridHeight)

                VStack(alignment: .leading, spacing: 8) {
                    if occurrences.isEmpty {
                        Text("这天还没有日程")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, 12)
                    } else {
                        ForEach(Array(occurrences.enumerated()), id: \.element.id) { index, occurrence in
                            TimelineEntry(occurrence: occurrence,
                                          day: selectedKey,
                                          isLast: index == occurrences.count - 1,
                                          onOpen: { onEdit(.edit(occurrence)) },
                                          onToggle: {
                                              withAnimation(.snappy(duration: 0.25)) {
                                                  store.toggleCompletion(eventId: occurrence.event.id,
                                                                         on: occurrence.startKey)
                                              }
                                          })
                        }
                    }
                }
                .padding(.horizontal, 18)
            }
            .padding(.bottom, 90)
        }
        .onAppear { position = Self.monthIndex(day) }
        .onChange(of: position) { _, index in
            // 翻到别的月：本月选今天，其他月选 1 号
            guard let index, Self.monthIndex(day) != index else { return }
            day = index == Self.monthIndex(today)
                ? today
                : DayNumber.from(year: index / 12, month: index % 12 + 1, day: 1)
        }
        .onChange(of: day) { _, newDay in
            let index = Self.monthIndex(newDay)
            guard position != index else { return }
            withAnimation(.smooth(duration: 0.35)) { position = index }
        }
    }
}
