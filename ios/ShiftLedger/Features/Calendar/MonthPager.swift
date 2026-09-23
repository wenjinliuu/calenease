import Observation
import SwiftUI

/// 月历翻页器。
///
/// 用系统的分页 `ScrollView` 做：手指拖动时由系统滚动引擎直接驱动，跟手、带惯性，
/// 相邻的月份从卡片边缘一起滑进来。
///
/// 滑动时最要紧的是「手指底下什么都别重算」。这里分三层：
/// - `MonthPagerScroll` 装着真正的分页滚动。它是 `Equatable` 的，只在数据、选中状态、
///   查看的月份变了才重算，拖动过程中一次都不会；
/// - 高度随滑动插值时，只改一个小对象 `PagerRows` 里的行数，读它的只有外面那层
///   `PagerViewport`——它的 body 只有一个 frame，重算一次几乎不花钱；
/// - 而且行数只有在相邻两个月行数不同时才会变（5 行 ↔ 6 行），行数相同的两个月之间
///   滑动，整个拖动过程 SwiftUI 一次更新都没有。
///
/// 滚动视图本身固定按 6 行的高度排版，外层按插值出来的高度裁切，
/// 所以高度变化只影响外层一个 frame，不会让月历重新排版。
struct MonthPager: View {
    @Environment(ScheduleStore.self) private var store

    let batchMode: Bool
    let selectedDates: Set<String>
    let onSelect: (String) -> Void

    @State private var rows: PagerRows

    init(focusedIndex: Int,
         batchMode: Bool,
         selectedDates: Set<String>,
         onSelect: @escaping (String) -> Void) {
        self.batchMode = batchMode
        self.selectedDates = selectedDates
        self.onSelect = onSelect
        _rows = State(initialValue: PagerRows(value: CGFloat(CalendarMonthGrid.rows(index: focusedIndex))))
    }

    /// 多选时每格底下挂一枚勾，落在行距里；最后一行的勾要多留这点地方。
    private var bottomSlack: CGFloat { batchMode ? 10 : 0 }

    var body: some View {
        let document = store.document
        let display = document.display
        let focusStore = store
        PagerViewport(rows: rows, display: display, bottomSlack: bottomSlack) {
            MonthPagerScroll(document: document,
                             todayKey: focusStore.todayKey,
                             focusedIndex: focusStore.focusedIndex,
                             batchMode: batchMode,
                             selectedDates: selectedDates,
                             holidays: focusStore.holidays,
                             contentHeight: CalendarMonthGrid.height(rows: 6, display: display) + bottomSlack,
                             rows: rows,
                             onSelect: onSelect,
                             onSettle: { index in
                                 withAnimation(.snappy(duration: 0.3)) { focusStore.focus(index: index) }
                             })
                .equatable()
        }
    }
}

/// 滑动过程中插值出来的行数。单独放一个对象里，只有 `PagerViewport` 读它。
@Observable
final class PagerRows {
    var value: CGFloat
    init(value: CGFloat) { self.value = value }
}

/// 按插值行数裁出可见高度。
private struct PagerViewport<Content: View>: View {
    let rows: PagerRows
    let display: CalendarDisplaySettings
    let bottomSlack: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(height: CalendarMonthGrid.height(rows: rows.value, display: display) + bottomSlack,
                   alignment: .top)
            .clipped()
    }
}

private struct MonthPagerScroll: View, Equatable {
    let document: ScheduleDocument
    let todayKey: String
    let focusedIndex: Int
    let batchMode: Bool
    let selectedDates: Set<String>
    let holidays: HolidayCalendar
    let contentHeight: CGFloat
    let rows: PagerRows
    let onSelect: (String) -> Void
    let onSettle: (Int) -> Void

    @State private var position: Int?

    init(document: ScheduleDocument,
         todayKey: String,
         focusedIndex: Int,
         batchMode: Bool,
         selectedDates: Set<String>,
         holidays: HolidayCalendar,
         contentHeight: CGFloat,
         rows: PagerRows,
         onSelect: @escaping (String) -> Void,
         onSettle: @escaping (Int) -> Void) {
        self.document = document
        self.todayKey = todayKey
        self.focusedIndex = focusedIndex
        self.batchMode = batchMode
        self.selectedDates = selectedDates
        self.holidays = holidays
        self.contentHeight = contentHeight
        self.rows = rows
        self.onSelect = onSelect
        self.onSettle = onSettle
        _position = State(initialValue: focusedIndex)
    }

    nonisolated static func == (lhs: MonthPagerScroll, rhs: MonthPagerScroll) -> Bool {
        lhs.focusedIndex == rhs.focusedIndex && lhs.todayKey == rhs.todayKey
            && lhs.batchMode == rhs.batchMode && lhs.selectedDates == rhs.selectedDates
            && lhs.contentHeight == rhs.contentHeight && lhs.rows === rhs.rows
            && lhs.holidays == rhs.holidays && lhs.document == rhs.document
    }

    /// 前后各五十年，足够翻。`LazyHStack` 只建看得见的那两三页。
    static let range: Range<Int> = {
        let parts = ScheduleCalendar.calendar.dateComponents([.year, .month], from: Date())
        let current = (parts.year ?? 2026) * 12 + (parts.month ?? 1) - 1
        return (current - 600)..<(current + 600)
    }()

    var body: some View {
        let lowerBound = Self.range.lowerBound
        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(Self.range, id: \.self) { index in
                    CalendarMonthGrid(year: index / 12,
                                      month: index % 12,
                                      document: document,
                                      todayKey: todayKey,
                                      batchMode: batchMode,
                                      selectedDates: selectedDates,
                                      holidays: holidays,
                                      onSelect: onSelect)
                        .equatable()
                        .frame(height: contentHeight, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: contentHeight)
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        // 只把「插值后的行数」交出去，而且量化到 1/50 行。相邻两月行数相同时它是个常数，
        // 系统判定没变化就不会回调——拖动全程零更新。
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            let width = geometry.containerSize.width
            guard width > 0 else { return -1 }
            let page = geometry.contentOffset.x / width
            let lower = page.rounded(.down)
            let index = lowerBound + Int(lower)
            let first = CGFloat(CalendarMonthGrid.rows(index: index))
            let second = CGFloat(CalendarMonthGrid.rows(index: index + 1))
            let blended = first + (second - first) * (page - lower)
            return (blended * 50).rounded() / 50
        } action: { _, newValue in
            if newValue > 0 { rows.value = newValue }
        }
        .onScrollPhaseChange { _, phase in
            // 停稳了再把月份交给 store。拖到一半就切的话，整页的本月概览会在手指底下重算。
            guard phase == .idle, let position, position != focusedIndex else { return }
            onSettle(position)
        }
        .onChange(of: focusedIndex) { _, target in
            // 按钮、月份选择器、统计页改了月份，翻页器跟过去：相邻月份滑过去，远的直接跳。
            guard position != target else { return }
            if let position, abs(position - target) == 1 {
                withAnimation(.smooth(duration: 0.38)) { self.position = target }
            } else {
                var transaction = Transaction()
                transaction.disablesAnimations = true
                withTransaction(transaction) { self.position = target }
            }
        }
    }
}
