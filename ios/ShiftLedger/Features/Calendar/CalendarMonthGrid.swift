import SwiftUI

/// 月历网格。
///
/// 格子本身不填底色（除了「今天」那一格），整块网格坐在一张白卡上。日期数字是主角，
/// 颜色只剩一枚 13pt 色标。格子左右各留一条 9pt 的标记列：
/// 左列放职责标签（这天我承担什么），右列放「休 / 班」（这天在日历上是什么性质）。
/// 两类信息含义不同，分开放比挤在一列清楚，日期也因此真正居中。
///
/// 格子高度贴合内容，留白放在行与行之间。日程色条跨格子画，整行一层盖在格子上。
/// 反过来做（格子撑高、行距 1pt）会让「今天」那一格的填充下方空出一大块。
///
/// 网格是 `Equatable` 的：左右滑动时外层每一帧都在变，但只要这个月的数据没变，
/// 网格就不用重算——比较时跳过 `onSelect` 这个闭包（闭包没法比较，
/// 带着它 SwiftUI 只能每帧都重画整月）。
struct CalendarMonthGrid: View, Equatable {
    let year: Int
    let month: Int
    let document: ScheduleDocument
    let todayKey: String
    var batchMode: Bool = false
    var selectedDates: Set<String> = []
    var holidays: HolidayCalendar = .empty
    /// 单选的那一天（外圈蓝环）。只传本月的，别的月传 nil，翻页时就不会连带重画。
    var selectedDay: String?
    let onSelect: (String) -> Void

    nonisolated static func == (lhs: CalendarMonthGrid, rhs: CalendarMonthGrid) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.todayKey == rhs.todayKey
            && lhs.batchMode == rhs.batchMode && lhs.selectedDates == rhs.selectedDates
            && lhs.selectedDay == rhs.selectedDay
            && lhs.holidays == rhs.holidays && lhs.document == rhs.document
    }

    private var layout: CellLayout { CellLayout(document: document) }
    private var cellHeight: CGFloat { DayCellMetrics.height(for: layout) }

    /// 这个月的记录按日期建一次索引。`document.record(on:)` 是整表线性查找，
    /// 一个月三十格就要把全部记录扫三十遍。
    private var monthRecords: [String: DayRecord] {
        let prefix = ScheduleCalendar.monthKey(year: year, month: month)
        var map: [String: DayRecord] = [:]
        for record in document.records where record.monthKey == prefix {
            map[record.date] = record
        }
        return map
    }

    /// 这个月里所有日程的发生情况，整月算一次，再按周切。
    private func monthOccurrences(blanks: Int, days: Int) -> [EventOccurrence] {
        guard !document.events.isEmpty else { return [] }
        let first = DayNumber.from(year: year, month: month + 1, day: 1)
        return EventEngine.occurrences(of: document.events,
                                       from: first,
                                       to: first + days - 1,
                                       shiftDays: EventEngine.shiftDays(of: document))
    }

    var body: some View {
        let records = monthRecords
        let layout = layout
        VStack(spacing: 10) {
            HStack(spacing: DayCellMetrics.columnSpacing) {
                ForEach(Array(ScheduleCalendar.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            // 一个月最多 42 格，直接排出来。原来用 `LazyVGrid`，放在横向分页里等于
            // 懒加载套懒加载，每翻进一页都要多走一轮测量，得不偿失。
            let blanks = ScheduleCalendar.leadingBlanks(year: year, month: month)
            let days = ScheduleCalendar.daysInMonth(year: year, month: month)
            let occurrences = monthOccurrences(blanks: blanks, days: days)
            let firstDay = DayNumber.from(year: year, month: month + 1, day: 1)
            VStack(spacing: DayCellMetrics.rowSpacing) {
                ForEach(0..<Self.rows(blanks: blanks, days: days), id: \.self) { row in
                    HStack(spacing: DayCellMetrics.columnSpacing) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = row * 7 + column - blanks + 1
                            if day >= 1 && day <= days {
                                cell(day: day, records: records, layout: layout)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: cellHeight)
                            }
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if !occurrences.isEmpty {
                            let firstColumn = row == 0 ? blanks : 0
                            let lastColumn = min(6, days + blanks - 1 - row * 7)
                            let week = EventEngine.layoutWeek(occurrences,
                                                              weekStart: firstDay - blanks + row * 7,
                                                              visibleColumns: firstColumn...lastColumn,
                                                              lanes: layout.eventSlots)
                            if !week.segments.isEmpty || !week.hidden.isEmpty {
                                WeekEventBars(segments: week.segments,
                                              hidden: week.hidden,
                                              weekStart: firstDay - blanks + row * 7,
                                              top: DayCellMetrics.barsTop(for: layout),
                                              slots: layout.eventSlots)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(day: Int, records: [String: DayRecord], layout: CellLayout) -> some View {
        let key = ScheduleCalendar.key(year: year, month: month, day: day)
        let display = document.display
        return DayCell(day: day,
                       key: key,
                       record: records[key],
                       document: document,
                       isToday: key == todayKey,
                       lunarText: display.showLunar ? LunarCalendar.text(for: key) : nil,
                       festival: display.showLunar || display.showHolidays ? Festivals.festival(on: key) : nil,
                       adjustment: display.showHolidays ? holidays.adjustment(on: key) : nil,
                       batchMode: batchMode,
                       isSelected: selectedDates.contains(key),
                       isFocused: !batchMode && key == selectedDay,
                       layout: layout,
                       height: cellHeight)
            .contentShape(RoundedRectangle(cornerRadius: DayCellMetrics.corner, style: .continuous))
            .onTapGesture { onSelect(key) }
    }

    static func rows(blanks: Int, days: Int) -> Int { (blanks + days + 6) / 7 }

    private static let rowsLock = NSLock()
    private static var rowsCache: [Int: Int] = [:]

    /// `index` 是「年 × 12 + 零基月」。翻页时每一帧都要问相邻两个月各几行，记下来不重算。
    static func rows(index: Int) -> Int {
        if let cached = rowsLock.withLock({ rowsCache[index] }) { return cached }
        let year = index / 12, month = index % 12
        let value = rows(blanks: ScheduleCalendar.leadingBlanks(year: year, month: month),
                         days: ScheduleCalendar.daysInMonth(year: year, month: month))
        rowsLock.withLock { rowsCache[index] = value }
        return value
    }

    /// 整块网格的高度（星期表头 + 表头间距 + 每行格子与行距）。行数可以带小数，
    /// 滑动切月时在 5 行和 6 行之间插值用。
    static func height(rows: CGFloat, layout: CellLayout) -> CGFloat {
        let cell = DayCellMetrics.height(for: layout)
        return 13 + 10 + rows * cell + max(rows - 1, 0) * DayCellMetrics.rowSpacing
    }

    static func height(year: Int, month: Int, layout: CellLayout) -> CGFloat {
        height(rows: CGFloat(rows(index: year * 12 + month)), layout: layout)
    }
}

/// 格子里要排哪几行。显示设置和「排班功能」开关一起决定，关掉的行整行收起，下面的往上补。
struct CellLayout: Hashable {
    var lunar: Bool
    var shiftRow: Bool
    var timeRow: Bool
    var eventSlots: Int

    init(document: ScheduleDocument) {
        let display = document.display
        lunar = display.showLunar
        shiftRow = document.features.shiftsEnabled
        timeRow = shiftRow && display.showShiftTime
        eventSlots = min(3, max(0, display.eventSlots))
    }
}

/// 一周的日程色条，盖在这一行格子上面。
///
/// 色条跨格子画，所以不放在格子里，而是整行一层；不接收点按，点按还是落到下面的格子。
private struct WeekEventBars: View {
    let segments: [EventBarSegment]
    let hidden: [Int: Int]
    let weekStart: Int
    let top: CGFloat
    let slots: Int

    var body: some View {
        GeometryReader { proxy in
            let spacing = DayCellMetrics.columnSpacing
            let columnWidth = (proxy.size.width - spacing * 6) / 7
            ForEach(segments) { segment in
                let tone = Tone.event(segment.occurrence.event.color)
                let continues = segment.occurrence.end > weekStart + segment.column + segment.span - 1
                let width = CGFloat(segment.span) * columnWidth + CGFloat(segment.span - 1) * spacing
                Text(segment.occurrence.event.title)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(tone.ink)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.horizontal, 3)
                    .frame(width: width - 4, height: DayCellMetrics.barHeight, alignment: .leading)
                    // 色条带一点透明：跨过选中那天时，底下的蓝圈隐约透出来，不被整段盖住
                    .background(tone.fill.opacity(0.78), in: UnevenRoundedRectangle(
                        topLeadingRadius: segment.startsHere ? 3.5 : 0,
                        bottomLeadingRadius: segment.startsHere ? 3.5 : 0,
                        bottomTrailingRadius: continues ? 0 : 3.5,
                        topTrailingRadius: continues ? 0 : 3.5,
                        style: .continuous))
                    .offset(x: CGFloat(segment.column) * (columnWidth + spacing) + (segment.startsHere ? 2 : 0),
                            y: top + CGFloat(segment.lane) * (DayCellMetrics.barHeight + DayCellMetrics.barGap))
            }
            ForEach(hidden.keys.sorted(), id: \.self) { column in
                Text("+\(hidden[column] ?? 0)")
                    .font(.system(size: 7.5, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(width: columnWidth - 4, alignment: .trailing)
                    .offset(x: CGFloat(column) * (columnWidth + spacing),
                            y: top + CGFloat(slots) * (DayCellMetrics.barHeight + DayCellMetrics.barGap) - 1)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// 格子的几何。iPhone 上一格约 46pt 宽。
enum DayCellMetrics {
    /// 两侧标记列各占这么宽。原来各 11pt 时中间只剩 24pt，
    /// 而两位数日期在 22pt 字号下约 24pt 宽，正好顶满——挂了标签就会贴到一起。
    static let railWidth: CGFloat = 9
    static let dateRow: CGFloat = 22
    static let markRow: CGFloat = 13
    static let timeRow: CGFloat = 11
    /// 日期下面的农历 / 节日那一行，和日期之间只隔 1pt，读起来是一组。
    static let lunarRow: CGFloat = 10
    static let lunarGap: CGFloat = 1
    static let spacing: CGFloat = 4
    static let paddingTop: CGFloat = 8
    static let paddingBottom: CGFloat = 9
    static let corner: CGFloat = 10
    /// 选中蓝圈比格子往下多伸出的距离。
    static let focusOutset: CGFloat = 3
    /// 留白放在行与行之间，不放在格子里。日程色条占了一部分高度，行距收到 10pt。
    static let rowSpacing: CGFloat = 10
    static let columnSpacing: CGFloat = 1
    /// 日程色条。
    static let barHeight: CGFloat = 14
    static let barGap: CGFloat = 2

    /// 日程色条从格子顶上往下多少开始画。
    static func barsTop(for layout: CellLayout) -> CGFloat {
        var top = paddingTop + dateRow
        if layout.lunar { top += lunarGap + lunarRow }
        if layout.shiftRow { top += spacing + markRow }
        if layout.timeRow { top += spacing + timeRow }
        return top + spacing
    }

    static func height(for layout: CellLayout) -> CGFloat {
        var height = barsTop(for: layout) - spacing + paddingBottom
        if layout.eventSlots > 0 {
            height += spacing + CGFloat(layout.eventSlots) * (barHeight + barGap) - barGap
        }
        return height
    }
}

private struct DayCell: View {
    let day: Int
    let key: String
    let record: DayRecord?
    let document: ScheduleDocument
    let isToday: Bool
    /// 农历开着时日期下面那一行；关着时是 nil。
    let lunarText: String?
    let festival: Festival?
    let adjustment: DayAdjustment?
    let batchMode: Bool
    let isSelected: Bool
    /// 单选选中的那一天：外面一圈蓝环。
    let isFocused: Bool
    let layout: CellLayout
    let height: CGFloat

    private var shift: ShiftDefinition? { record.flatMap { document.shift($0.shiftId) } }
    private var secondaryShift: ShiftDefinition? {
        record?.secondaryShiftId.flatMap { document.shift($0) }
    }
    private var tags: [DutyTag] { (record?.tagIds ?? []).compactMap { document.tag($0) } }

    /// 没有记录，或这一天被取消排班。
    private var isUnscheduled: Bool { record == nil || record?.planned == false }

    private var showsHours: Bool {
        guard let shift, let record else { return false }
        return document.display.showHours && document.work.trackHours
            && shift.countsAsWork && !shift.isRest && record.hours > 0
    }

    var body: some View {
        content
            .frame(maxWidth: .infinity)
            .frame(height: height, alignment: .top)
            .background {
                // 今天和多选选中用同一层淡底；选中另外还有一圈描边，分得开
                if isSelected || isToday {
                    RoundedRectangle(cornerRadius: DayCellMetrics.corner, style: .continuous)
                        .fill(Palette.todayFill)
                }
            }
            .overlay(alignment: .topLeading) { rail(tagMarks) }
            .overlay(alignment: .topTrailing) { rail(dateMarks) }
            .overlay(alignment: .bottom) { noteDot }
            .overlay {
                if isFocused {
                    // 往下多伸 3pt：右下角的「+N」落在格子底边上，不让蓝圈压住它
                    RoundedRectangle(cornerRadius: DayCellMetrics.corner, style: .continuous)
                        .strokeBorder(Palette.blue, lineWidth: 1.6)
                        .padding(.bottom, -DayCellMetrics.focusOutset)
                }
            }
            .overlay {
                // 多选时格子内容一个不藏——班次、工时、标签照常显示，改之前看得见原来是什么。
                // 可选的状态只靠外框表达：没选是一圈淡描边，选中是蓝框 + 底部一枚勾。
                if batchMode {
                    RoundedRectangle(cornerRadius: DayCellMetrics.corner, style: .continuous)
                        .strokeBorder(isSelected ? AnyShapeStyle(Palette.blue) : AnyShapeStyle(Palette.hairline),
                                      lineWidth: isSelected ? 1.6 : 1)
                }
            }
            .overlay(alignment: .bottom) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Palette.blue)
                        .background(Circle().fill(Palette.card).padding(1))
                        // 落在行与行之间的留白里，不挡格子里的字
                        .offset(y: 7)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isSelected)
            .animation(.snappy(duration: 0.2), value: isFocused)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("day-\(key)")
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - 主列

    private var content: some View {
        VStack(spacing: DayCellMetrics.spacing) {
            VStack(spacing: DayCellMetrics.lunarGap) {
                dateRow
                if let lunarText { lunarRow(lunarText) }
            }
            if layout.shiftRow { markRow }
            if layout.timeRow { timeRow }
        }
        .padding(.top, DayCellMetrics.paddingTop)
        // 只留 3pt。两位数日期在 22pt 字号下约 24pt 宽，在 46pt 的格子里居中后
        // 正好落在两条 9pt 标记列之间，不必再往里收；收多了「色标 + 工时」就放不下。
        .padding(.horizontal, 3)
    }

    /// 今天不改数字颜色，只把字重加到 bold——颜色留给班次和节假日。
    private var dateRow: some View {
        Text("\(day)")
            .font(.system(size: 22, weight: isToday || isFocused ? .bold : .medium))
            .monospacedDigit()
            // 日期颜色不跟排班走：平时一律黑字，选中的那天和蓝圈同色
            .foregroundStyle(isFocused ? AnyShapeStyle(Palette.blue) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: DayCellMetrics.dateRow)
    }

    /// 农历开着时日期下面一行：节日当天写节日（法定红、传统琥珀），平时写农历日子。
    private func lunarRow(_ lunarText: String) -> some View {
        Text(festival?.shortName ?? lunarText)
            .font(.system(size: 8.5, weight: festival == nil ? .medium : .semibold))
            .foregroundStyle(festival.map { AnyShapeStyle(Self.color(for: $0)) } ?? AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: DayCellMetrics.lunarRow)
    }

    private static func color(for festival: Festival) -> Color {
        festival.kind == .statutory ? Palette.holiday : Palette.traditionalFestival
    }

    @ViewBuilder
    private var markRow: some View {
        // 主要班次、次要班次、工时排在同一行。两枚色标永远完整显示（`fixedSize`），
        // 挤不下时只压工时：先收字距，再缩字号。
        let secondary = document.display.showShift ? secondaryShift : nil
        HStack(spacing: secondary == nil ? 3 : 2) {
            if isUnscheduled {
                Color.clear
            } else if let shift, shift.isRest {
                Text(shift.shortName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.restInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                if let secondary { shiftMark(secondary).fixedSize() }
            } else if let shift {
                if document.display.showShift { shiftMark(shift).fixedSize() }
                if let secondary { shiftMark(secondary).fixedSize() }
                if showsHours, let record {
                    Text(HoursFormatter.hours(record.hours))
                        .font(.system(size: secondary == nil ? 10 : 9.5, weight: .semibold))
                        .tracking(secondary == nil ? 0 : -0.5)
                        .monospacedDigit()
                        .foregroundStyle(shift.tone.text)
                        .lineLimit(1)
                        .minimumScaleFactor(secondary == nil ? 0.75 : 0.55)
                }
            }
        }
        .frame(height: DayCellMetrics.markRow)
    }

    /// 13pt 色标。简称超过一个字时撑成胶囊，不压字。
    private func shiftMark(_ shift: ShiftDefinition) -> some View {
        let tone = shift.tone
        let isWide = shift.shortName.count > 1
        return Text(shift.shortName)
            .font(.system(size: isWide ? 7.5 : 9.5, weight: .bold))
            .foregroundStyle(tone.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, isWide ? 3 : 0)
            .frame(width: isWide ? nil : DayCellMetrics.markRow, height: DayCellMetrics.markRow)
            .background(tone.mark, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
    }

    @ViewBuilder
    private var timeRow: some View {
        if let shift, !shift.fullRange.isEmpty, !shift.isRest {
            Text(shift.fullRange)
                .font(.system(size: 8, weight: .medium))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(height: DayCellMetrics.timeRow)
        } else {
            Color.clear.frame(height: DayCellMetrics.timeRow)
        }
    }

    // MARK: - 两侧标记列

    /// 右列：这一天在日历上是什么性质。
    ///
    /// 上面是「休」（红）或「班」（蓝），来自国务院的放假安排；
    /// 农历关着时，节日名也放在这一列，排在「休 / 班」下面。
    private var dateMarks: [AnyView] {
        var marks: [AnyView] = []
        switch adjustment {
        case .off:
            marks.append(AnyView(Self.adjustmentMark("休", color: Palette.holiday)))
        case .work:
            marks.append(AnyView(Self.adjustmentMark("班", color: Palette.adjustedWorkday)))
        case nil:
            break
        }
        if lunarText == nil, let festival {
            marks.append(AnyView(
                Text(festival.shortName)
                    .font(.system(size: 7.5, weight: .semibold))
                    .foregroundStyle(Self.color(for: festival))
                    .lineLimit(2)
                    .minimumScaleFactor(0.8)
            ))
        }
        return marks
    }

    private static func adjustmentMark(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .bold))
            .foregroundStyle(color)
            .lineLimit(1)
    }

    /// 左列：这一天我承担什么。最多排三个，多的收成「＋n」。
    private var tagMarks: [AnyView] {
        guard document.display.showTags, !tags.isEmpty else { return [] }
        var marks = tags.prefix(3).map { tag in
            AnyView(
                Text(tag.shortName.prefix(1))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(tag.inkOnSurface)
                    .lineLimit(1)
            )
        }
        if tags.count > 3 {
            marks.append(AnyView(
                Text("＋\(tags.count - 3)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            ))
        }
        return marks
    }

    @ViewBuilder
    private func rail(_ marks: [AnyView]) -> some View {
        if marks.isEmpty {
            EmptyView()
        } else {
            VStack(spacing: 2.5) {
                ForEach(Array(marks.enumerated()), id: \.offset) { _, mark in mark }
            }
            .frame(width: DayCellMetrics.railWidth)
            // 顺着圆角往里、往上收一点，选中的蓝圈不会压到角上的字
            .padding(.top, 3.5)
            .padding(.horizontal, 2)
        }
    }

    @ViewBuilder
    private var noteDot: some View {
        if let note = record?.note, !note.isEmpty {
            Circle()
                .fill(.tertiary)
                .frame(width: 4, height: 4)
                .padding(.bottom, 3)
                .accessibilityHidden(true)
        }
    }

    // MARK: - 细节


    private var accessibilityText: String {
        var parts = ["\(day)日"]
        if isToday { parts.append("今天") }
        if isFocused { parts.append("已选中") }
        if batchMode { parts.append(isSelected ? "已选中" : "未选中") }
        if let festival { parts.append(festival.name) }
        switch adjustment {
        case .off: parts.append("放假")
        case .work: parts.append("调休上班")
        case nil: break
        }
        if let lunarText, festival == nil { parts.append("农历\(lunarText)") }
        if !layout.shiftRow {
            // 不排班的人不念班次
        } else if let shift {
            parts.append(shift.name)
            if let secondaryShift { parts.append("次要班次\(secondaryShift.name)") }
            if !shift.fullRange.isEmpty { parts.append(shift.fullRange) }
        } else {
            parts.append("未排班")
        }
        if showsHours, let record { parts.append("\(HoursFormatter.compact(record.hours))小时") }
        parts.append(contentsOf: tags.map(\.name))
        if let note = record?.note, !note.isEmpty { parts.append("有备注") }
        return parts.joined(separator: "，")
    }
}
