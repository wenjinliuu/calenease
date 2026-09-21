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
struct CalendarMonthGrid: View {
    let year: Int
    let month: Int
    let document: ScheduleDocument
    let todayKey: String
    var batchMode: Bool = false
    var batchDates: [String] = []
    let onSelect: (String) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DayCellMetrics.columnSpacing),
                                count: 7)

    private var cellHeight: CGFloat { DayCellMetrics.height(for: document.display) }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: DayCellMetrics.columnSpacing) {
                ForEach(Array(ScheduleCalendar.weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: DayCellMetrics.rowSpacing) {
                ForEach(Array(0..<ScheduleCalendar.leadingBlanks(year: year, month: month)), id: \.self) { index in
                    Color.clear
                        .frame(height: cellHeight)
                        .id("blank-\(index)")
                }
                ForEach(Array(1...ScheduleCalendar.daysInMonth(year: year, month: month)), id: \.self) { day in
                    let key = ScheduleCalendar.key(year: year, month: month, day: day)
                    DayCell(day: day,
                            key: key,
                            record: document.record(on: key),
                            document: document,
                            isToday: key == todayKey,
                            holiday: document.display.showHolidays ? Holidays.name(of: key) : "",
                            batchMode: batchMode,
                            batchIndex: batchDates.firstIndex(of: key),
                            batchCount: batchDates.count,
                            height: cellHeight)
                        .contentShape(RoundedRectangle(cornerRadius: DayCellMetrics.corner, style: .continuous))
                        .onTapGesture { onSelect(key) }
                }
            }
        }
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
    let batchIndex: Int?
    let batchCount: Int
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
                if isToday {
                    RoundedRectangle(cornerRadius: DayCellMetrics.corner, style: .continuous)
                        .fill(Palette.todayFill)
                }
            }
            .overlay(alignment: .topLeading) { rail(tagMarks) }
            .overlay(alignment: .topTrailing) { rail(dateMarks) }
            .overlay(alignment: .bottom) { noteDot }
            .overlay {
                if batchIndex != nil {
                    RoundedRectangle(cornerRadius: DayCellMetrics.corner, style: .continuous)
                        .strokeBorder(Palette.blue, lineWidth: 1.6)
                }
            }
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
            if batchMode {
                Text(batchBadge)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(batchIndex == nil ? AnyShapeStyle(.quaternary) : AnyShapeStyle(Palette.blue))
            } else if isUnscheduled {
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

    private var batchBadge: String {
        guard let batchIndex else { return "·" }
        if batchIndex == 0 { return "始" }
        if batchIndex == batchCount - 1, batchCount > 1 { return "止" }
        return "✓"
    }

    private var accessibilityText: String {
        var parts = ["\(day)日"]
        if isToday { parts.append("今天") }
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
