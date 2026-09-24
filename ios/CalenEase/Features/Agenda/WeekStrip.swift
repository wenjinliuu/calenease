import SwiftUI

/// 一周的日期条：周一到周日七格，左右滑动翻周。每格上面星期、中间日期、下面当天日程的彩色小点。
///
/// 事项页的日视图、周视图，日历页点开的当天时间轴，三处用的都是这一条，大小、配色、小点一模一样。
/// 周视图要和下面的时间格子列对齐，所以左右留白可以调（`leading` 放刻度栏的宽度）。
struct WeekStrip: View {
    @Binding var day: Int
    let today: Int
    var leading: CGFloat = 8
    var trailing: CGFloat = 8

    @Environment(ScheduleStore.self) private var store
    @State private var weekPosition: Int?

    static func weekStart(_ day: Int) -> Int { day - DayNumber.weekday(day) }

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
                            let number = start + offset
                            WeekDayCell(number: number,
                                        isSelected: number == day,
                                        isToday: number == today,
                                        colors: Self.colors(store.occurrences(on: DayNumber.key(number)))) {
                                withAnimation(.smooth(duration: 0.3)) { day = number }
                            }
                        }
                    }
                    .padding(.leading, leading)
                    .padding(.trailing, trailing)
                    .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.viewAligned(limitBehavior: .alwaysByOne))
        .scrollIndicators(.hidden)
        .scrollPosition(id: $weekPosition)
        .frame(height: WeekDayCell.height)
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

    /// 当天日程的颜色，去重后最多三个。
    static func colors(_ occurrences: [EventOccurrence]) -> [String] {
        var seen: [String] = []
        for occurrence in occurrences where !seen.contains(occurrence.event.color) {
            seen.append(occurrence.event.color)
            if seen.count == 3 { break }
        }
        return seen
    }
}

/// 日期条里的一格。今天是蓝字，选中的那天蓝底白字（省心日历的主色）。
struct WeekDayCell: View {
    let number: Int
    let isSelected: Bool
    let isToday: Bool
    let colors: [String]
    let onTap: () -> Void

    static let height: CGFloat = 60

    var body: some View {
        let date = DayNumber.civil(number)
        let weekday = ScheduleCalendar.weekdaySymbols[DayNumber.weekday(number)]
        Button(action: onTap) {
            VStack(spacing: 3) {
                // 每月 1 号写月份，翻周时一眼看到跨月了
                Text(date.day == 1 ? "\(date.month)月" : weekday)
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(date.day == 1 ? AnyShapeStyle(Palette.blue) : AnyShapeStyle(.secondary))
                Text("\(date.day)")
                    .font(.system(size: 16, weight: isSelected || isToday ? .bold : .medium))
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                                     : isToday ? AnyShapeStyle(Palette.blue) : AnyShapeStyle(.primary))
                    // 字重直接切，不做插值（插值时字形会先挤后撑）；位置照常跟着动画走
                    .contentTransition(.identity)
                    .frame(width: 32, height: 32)
                    .background {
                        Circle()
                            .fill(Palette.blue)
                            .opacity(isSelected ? 1 : 0)
                    }
                HStack(spacing: 2.5) {
                    ForEach(colors, id: \.self) { hex in
                        Circle().fill(Tone.event(hex).solid).frame(width: 5, height: 5)
                    }
                }
                .frame(height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(date.month)月\(date.day)日 周\(weekday)\(colors.isEmpty ? "" : "，有日程")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
