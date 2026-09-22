import SwiftUI

/// 月历网格。
///
/// 格子本身不填底色（除了「今天」那一格），整块网格坐在一张白卡上。日期数字是主角，
/// 颜色只剩一枚 13pt 色标。格子左右各留一条 9pt 的标记列：
/// 左列放职责标签（这天我承担什么），右列放法定节假日（这天在日历上是什么性质）。
/// 两类信息含义不同，分开放比挤在一列清楚，日期也因此真正居中。
///
/// 格子高度贴合内容，留白放在行与行之间——行距 17pt。
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
    let onSelect: (String) -> Void

    nonisolated static func == (lhs: CalendarMonthGrid, rhs: CalendarMonthGrid) -> Bool {
        lhs.year == rhs.year && lhs.month == rhs.month && lhs.todayKey == rhs.todayKey
            && lhs.batchMode == rhs.batchMode && lhs.selectedDates == rhs.selectedDates
            && lhs.document == rhs.document
    }

    private var cellHeight: CGFloat { DayCellMetrics.height(for: document.display) }

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

    var body: some View {
        let records = monthRecords
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
            VStack(spacing: DayCellMetrics.rowSpacing) {
                ForEach(0..<Self.rows(blanks: blanks, days: days), id: \.self) { row in
                    HStack(spacing: DayCellMetrics.columnSpacing) {
                        ForEach(0..<7, id: \.self) { column in
                            let day = row * 7 + column - blanks + 1
                            if day >= 1 && day <= days {
                                cell(day: day, records: records)
                            } else {
                                Color.clear
                                    .frame(maxWidth: .infinity)
                                    .frame(height: cellHeight)
                            }
                        }
                    }
                }
            }
        }
    }

    private func cell(day: Int, records: [String: DayRecord]) -> some View {
        let key = ScheduleCalendar.key(year: year, month: month, day: day)
        return DayCell(day: day,
                       key: key,
                       record: records[key],
                       document: document,
                       isToday: key == todayKey,
                       holiday: document.display.showHolidays ? Holidays.name(of: key) : "",
                       batchMode: batchMode,
                       isSelected: selectedDates.contains(key),
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
    static func height(rows: CGFloat, display: CalendarDisplaySettings) -> CGFloat {
        let cell = DayCellMetrics.height(for: display)
        return 13 + 10 + rows * cell + max(rows - 1, 0) * DayCellMetrics.rowSpacing
    }

    static func height(year: Int, month: Int, display: CalendarDisplaySettings) -> CGFloat {
        height(rows: CGFloat(rows(index: year * 12 + month)), display: display)
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
    static let spacing: CGFloat = 4
    static let paddingTop: CGFloat = 8
    static let paddingBottom: CGFloat = 9
    static let corner: CGFloat = 10
    /// 留白放在行与行之间，不放在格子里。
    static let rowSpacing: CGFloat = 17
    static let columnSpacing: CGFloat = 1

    static func height(for display: CalendarDisplaySettings) -> CGFloat {
        var height = paddingTop + dateRow + paddingBottom
        height += spacing + markRow
        if display.showShiftTime { height += spacing + timeRow }
        return height
    }
}

private struct DayCell: View {
    let day: Int
    let key: String
    let record: DayRecord?
    let document: ScheduleDocument
    let isToday: Bool
    let holiday: String
    let batchMode: Bool
    let isSelected: Bool
    let height: CGFloat

    private var shift: ShiftDefinition? { record.flatMap { document.shift($0.shiftId) } }
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
            .frame(height: height)
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
                        .offset(y: 8)
                        .transition(.scale(scale: 0.4).combined(with: .opacity))
                        .accessibilityHidden(true)
                }
            }
            .animation(.spring(response: 0.26, dampingFraction: 0.7), value: isSelected)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("day-\(key)")
            .accessibilityLabel(accessibilityText)
            .accessibilityAddTraits(.isButton)
    }

    // MARK: - 主列

    private var content: some View {
        VStack(spacing: DayCellMetrics.spacing) {
            dateRow
            markRow
            if document.display.showShiftTime { timeRow }
        }
        .padding(.top, DayCellMetrics.paddingTop)
        .padding(.bottom, DayCellMetrics.paddingBottom)
        // 只留 3pt。两位数日期在 22pt 字号下约 24pt 宽，在 46pt 的格子里居中后
        // 正好落在两条 9pt 标记列之间，不必再往里收；收多了「色标 + 工时」就放不下。
        .padding(.horizontal, 3)
    }

    /// 今天不改数字颜色，只把字重加到 bold——颜色留给班次和节假日。
    private var dateRow: some View {
        Text("\(day)")
            .font(.system(size: 22, weight: isToday ? .bold : .medium))
            .monospacedDigit()
            .foregroundStyle(isUnscheduled || shift?.isRest == true ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.primary))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(height: DayCellMetrics.dateRow)
    }

    @ViewBuilder
    private var markRow: some View {
        HStack(spacing: 3) {
            if isUnscheduled {
                Color.clear
            } else if let shift, shift.isRest {
                Text(shift.shortName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Palette.restInk)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            } else if let shift {
                if document.display.showShift { shiftMark(shift) }
                if showsHours, let record {
                    Text(HoursFormatter.hours(record.hours))
                        .font(.system(size: 10, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(shift.tone.text)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
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
    /// 设计里这一列还留了「调休上班」的绿色「班」字（本该休却要上，含义与节假日相反），
    /// 但数据层目前没有调休来源——`Holidays` 只判定法定节假日——所以先只渲染节假日。
    private var dateMarks: [AnyView] {
        guard !holiday.isEmpty else { return [] }
        return [AnyView(
            Text(Holidays.shortName(holiday))
                .font(.system(size: 7.5, weight: .semibold))
                .foregroundStyle(Palette.holiday)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        )]
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
            .padding(.top, 5)
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
        if batchMode { parts.append(isSelected ? "已选中" : "未选中") }
        if !holiday.isEmpty { parts.append(holiday) }
        if let shift {
            parts.append(shift.name)
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
