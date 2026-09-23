import SwiftUI

/// 一天的时间轴。左右滑动换天，左边是 0–24 点刻度，日程按时间画成色块；
/// 点空白处在那个钟点新建日程。
struct DayTimelineSheet: View {
    let startDate: String

    @Environment(ScheduleStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var position: Int?
    @State private var editorTarget: EventEditorTarget?

    private let range: ClosedRange<Int>

    init(startDate: String) {
        self.startDate = startDate
        let day = DayNumber.of(startDate) ?? 0
        range = (day - 366)...(day + 366)
        _position = State(initialValue: day)
    }

    private var currentDay: Int { position ?? DayNumber.of(startDate) ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView(.horizontal) {
                LazyHStack(spacing: 0) {
                    ForEach(range, id: \.self) { day in
                        DayTimelinePage(day: day) { target in editorTarget = target }
                            .containerRelativeFrame(.horizontal)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.paging)
            .scrollIndicators(.hidden)
            .scrollPosition(id: $position)
            .background(Palette.canvas)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("今天") {
                        withAnimation(.smooth(duration: 0.35)) { position = DayNumber.of(store.todayKey) }
                    }
                    .disabled(DayNumber.of(store.todayKey) == currentDay)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        editorTarget = .new(on: DayNumber.key(currentDay), reminders: store.document.reminders)
                    } label: {
                        Label("新建日程", systemImage: "plus")
                    }
                }
            }
            .sheet(item: $editorTarget) { target in
                EventEditorSheet(target: target)
            }
            .sensoryFeedback(.selection, trigger: position)
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var title: String {
        let key = DayNumber.key(currentDay)
        let date = DayNumber.civil(currentDay)
        let weekday = ScheduleCalendar.weekdaySymbols[DayNumber.weekday(currentDay)]
        var text = "\(date.month)月\(date.day)日 周\(weekday)"
        if key == store.todayKey { text += " · 今天" }
        return text
    }
}

/// 时间轴上的一天。
private struct DayTimelinePage: View {
    let day: Int
    let onEdit: (EventEditorTarget) -> Void

    @Environment(ScheduleStore.self) private var store

    private static let hourHeight: CGFloat = 48
    private static let gutter: CGFloat = 46

    private var key: String { DayNumber.key(day) }
    private var document: ScheduleDocument { store.document }

    var body: some View {
        let occurrences = store.occurrences(on: key)
        let allDay = occurrences.filter { $0.event.isAllDay }
        let timed = occurrences.filter { !$0.event.isAllDay }
        let record = document.features.shiftsEnabled ? document.record(on: key) : nil
        let shift = record.flatMap { $0.planned ? document.shift($0.shiftId) : nil }

        VStack(spacing: 0) {
            if shift != nil || !allDay.isEmpty {
                allDayStrip(shift: shift, events: allDay)
                Divider()
            }
            ScrollViewReader { proxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        hourGrid
                        if let shift, !shift.isRest { shiftBand(shift) }
                        blocks(timed)
                        if key == store.todayKey { nowLine }
                    }
                    .frame(height: Self.hourHeight * 24 + 16)
                    .padding(.top, 8)
                }
                .onAppear { proxy.scrollTo(7, anchor: .top) }
            }
        }
    }

    // MARK: - 全天

    private func allDayStrip(shift: ShiftDefinition?, events: [EventOccurrence]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 6) {
                if let shift {
                    HStack(spacing: 5) {
                        ShiftOrb(shift: shift, size: 18)
                        Text(shift.fullRange.isEmpty ? shift.name : "\(shift.name) \(shift.fullRange)")
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .frame(height: 28)
                    .background(Palette.card, in: Capsule())
                }
                ForEach(events) { occurrence in
                    let tone = Tone.event(occurrence.event.color)
                    Button { onEdit(.edit(occurrence)) } label: {
                        Text(occurrence.event.title)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tone.ink)
                            .lineLimit(1)
                            .padding(.horizontal, 10)
                            .frame(height: 28)
                            .background(tone.fill, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
    }

    // MARK: - 刻度

    private var hourGrid: some View {
        VStack(spacing: 0) {
            ForEach(0..<25, id: \.self) { hour in
                HStack(alignment: .top, spacing: 6) {
                    Text(hour == 24 ? "" : String(format: "%02d:00", hour))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.tertiary)
                        .frame(width: Self.gutter - 6, alignment: .trailing)
                        .offset(y: -6)
                    Rectangle()
                        .fill(Palette.hairline)
                        .frame(height: 0.5)
                }
                .frame(height: hour == 24 ? 1 : Self.hourHeight, alignment: .top)
                .id(hour)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(coordinateSpace: .local) { location in
            guard location.x > Self.gutter else { return }
            // 点在哪个半点就从哪个半点开始
            let minute = Int(location.y / Self.hourHeight * 2) * 30
            onEdit(.new(on: key, startMinute: max(0, min(23 * 60, minute)), reminders: document.reminders))
        }
    }

    /// 当天班次的时段：刻度右边一道淡色竖条。
    private func shiftBand(_ shift: ShiftDefinition) -> some View {
        let start = CGFloat(EventClock.minutes(shift.startTime) ?? 0)
        var end = CGFloat(EventClock.minutes(shift.endTime) ?? 0)
        if end <= start { end = 24 * 60 }
        return RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(shift.tint.opacity(0.35))
            .frame(width: 4, height: max(8, (end - start) / 60 * Self.hourHeight))
            .offset(x: Self.gutter - 2, y: start / 60 * Self.hourHeight)
            .allowsHitTesting(false)
            .accessibilityLabel("\(shift.name) \(shift.fullRange)")
    }

    private var nowLine: some View {
        let parts = ScheduleCalendar.calendar.dateComponents([.hour, .minute], from: Date())
        let minute = CGFloat((parts.hour ?? 0) * 60 + (parts.minute ?? 0))
        return HStack(spacing: 0) {
            Circle().fill(Palette.red).frame(width: 7, height: 7)
            Rectangle().fill(Palette.red).frame(height: 1)
        }
        .offset(x: Self.gutter - 3, y: minute / 60 * Self.hourHeight - 3.5)
        .allowsHitTesting(false)
    }

    // MARK: - 色块

    private func blocks(_ timed: [EventOccurrence]) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width - Self.gutter - 10
            ForEach(Self.layout(timed, day: day), id: \.occurrence.id) { item in
                let tone = Tone.event(item.occurrence.event.color)
                let columnWidth = width / CGFloat(item.columns)
                let height = max(22, CGFloat(item.end - item.start) / 60 * Self.hourHeight - 2)
                Button { onEdit(.edit(item.occurrence)) } label: {
                    HStack(spacing: 0) {
                        Rectangle().fill(tone.solid).frame(width: 3)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.occurrence.event.title)
                                .font(.caption.weight(.semibold))
                                .lineLimit(height > 40 ? 2 : 1)
                            if height > 34 {
                                Text(item.occurrence.event.timeLabel)
                                    .font(.caption2)
                                    .monospacedDigit()
                                    .opacity(0.8)
                            }
                        }
                        .foregroundStyle(tone.ink)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        Spacer(minLength: 0)
                    }
                    .frame(width: columnWidth - 2, height: height, alignment: .topLeading)
                    .background(tone.fill)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                .offset(x: Self.gutter + 4 + CGFloat(item.column) * columnWidth,
                        y: CGFloat(item.start) / 60 * Self.hourHeight + 1)
            }
        }
        .frame(height: Self.hourHeight * 24)
    }

    struct Placed {
        let occurrence: EventOccurrence
        let start: Int
        let end: Int
        var column: Int
        var columns: Int
    }

    /// 时间重叠的色块并排放：一组互相重叠的日程平分宽度。
    static func layout(_ occurrences: [EventOccurrence], day: Int) -> [Placed] {
        var items = occurrences.map { occurrence -> Placed in
            let event = occurrence.event
            let start = occurrence.start == day ? EventClock.minutes(event.startTime) ?? 0 : 0
            var end = occurrence.end == day ? EventClock.minutes(event.endTime) ?? 0 : 24 * 60
            if end <= start { end = min(24 * 60, start + 30) }
            return Placed(occurrence: occurrence, start: start, end: end, column: 0, columns: 1)
        }
        .sorted { $0.start != $1.start ? $0.start < $1.start : $0.end > $1.end }

        var groupStart = 0
        var groupEnd = -1
        var columnEnds: [Int] = []
        func closeGroup(upTo index: Int) {
            guard groupStart < index else { return }
            let count = max(1, columnEnds.count)
            for i in groupStart..<index { items[i].columns = count }
        }
        for index in items.indices {
            if items[index].start >= groupEnd {
                closeGroup(upTo: index)
                groupStart = index
                columnEnds = []
            }
            let column = columnEnds.firstIndex { $0 <= items[index].start } ?? columnEnds.count
            if column == columnEnds.count { columnEnds.append(items[index].end) } else { columnEnds[column] = items[index].end }
            items[index].column = column
            groupEnd = max(groupEnd, items[index].end)
        }
        closeGroup(upTo: items.count)
        return items
    }
}
