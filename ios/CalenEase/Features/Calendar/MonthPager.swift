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
    let selectedDay: String?
    let onSelect: (String) -> Void

    @State private var rows: PagerRows

    init(focusedIndex: Int,
         batchMode: Bool,
         selectedDates: Set<String>,
         selectedDay: String?,
         onSelect: @escaping (String) -> Void) {
        self.batchMode = batchMode
        self.selectedDates = selectedDates
        self.selectedDay = selectedDay
        self.onSelect = onSelect
        _rows = State(initialValue: PagerRows(value: CGFloat(CalendarMonthGrid.rows(index: focusedIndex))))
    }

    /// 多选时每格底下挂一枚勾，落在行距里；最后一行的勾要多留这点地方。
    private var bottomSlack: CGFloat { batchMode ? 10 : 0 }

    var body: some View {
        let document = store.document
        let layout = CellLayout(document: document)
        let focusStore = store
        PagerViewport(rows: rows, layout: layout, bottomSlack: bottomSlack) {
            MonthPagerScroll(document: document,
                             todayKey: focusStore.todayKey,
                             focusedIndex: focusStore.focusedIndex,
                             batchMode: batchMode,
                             selectedDates: selectedDates,
                             selectedDay: selectedDay,
                             holidays: focusStore.holidays,
                             contentHeight: CalendarMonthGrid.height(rows: 6, layout: layout) + bottomSlack,
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
    let layout: CellLayout
    let bottomSlack: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(height: CalendarMonthGrid.height(rows: rows.value, layout: layout) + bottomSlack,
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
    let selectedDay: String?
    let holidays: HolidayCalendar
    let contentHeight: CGFloat
    let rows: PagerRows
    let onSelect: (String) -> Void
    let onSettle: (Int) -> Void

    @State private var position: Int?
    /// 手指一松、分页滚动已经定下要停在哪一页时就记下来。翻页器正往那儿减速，
    /// 这时 store 跟着改月份，不能再反过来给滚动视图下一次「滚到那一页」的指令。
    @State private var settlingTarget: Int?
    /// 这一次拖动是从哪一页开始的。松手后只许停在它左右一页之内——
    /// 轻轻一甩不会越过下个月，减速途中系统再问一次目标也不会多翻一页。
    @State private var dragAnchor = PagerAnchor()

    init(document: ScheduleDocument,
         todayKey: String,
         focusedIndex: Int,
         batchMode: Bool,
         selectedDates: Set<String>,
         selectedDay: String?,
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
        self.selectedDay = selectedDay
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
            && lhs.selectedDay == rhs.selectedDay
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
                                      selectedDay: selectedDay.flatMap { day in
                                          day.hasPrefix(ScheduleCalendar.monthKey(year: index / 12, month: index % 12)) ? day : nil
                                      },
                                      onSelect: onSelect)
                        .equatable()
                        .frame(height: contentHeight, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .frame(height: contentHeight)
        // 松手那一刻就知道要停在哪一页：月份、选中的日子、震动都在这时候跟上，
        // 不用等减速动画走完——之前等到停稳才切，看着总慢半拍、不跟手。
        .scrollTargetBehavior(PagingWithTarget(anchor: dragAnchor) { page in
            let index = lowerBound + page
            guard index != focusedIndex, Self.range.contains(index) else { return }
            settlingTarget = index
            onSettle(index)
        })
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
            if phase == .interacting, dragAnchor.page == nil {
                // 手指按下：记住从哪一页开始拖（减速途中又按住的话，以正要停的那页为准）
                dragAnchor.page = (settlingTarget ?? position ?? focusedIndex) - lowerBound
            }
            // 停稳了再把月份交给 store。拖到一半就切的话，下面的日程面板会在手指底下重算。
            guard phase == .idle else { return }
            dragAnchor.page = nil
            settlingTarget = nil
            guard let position, position != focusedIndex else { return }
            onSettle(position)
        }
        .onChange(of: focusedIndex) { _, target in
            // 按钮、月份选择器、统计页改了月份，翻页器跟过去：相邻月份滑过去，远的直接跳。
            guard position != target, settlingTarget != target else { return }
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

/// 拖动起点。引用类型：分页规则在滚动引擎里被调用，读它不触发重算。
final class PagerAnchor {
    var page: Int?
}

/// 按页对齐、一次最多翻一页，外加一个回调：手指松开、目标页一定下来就报出第几页。
///
/// 原来用系统的 `.paging`：甩得稍快就会被惯性带过两页（9 月一甩到了 11 月），
/// 减速时又慢吞吞地滑。改成 `viewAligned(limitBehavior: .alwaysByOne)`，
/// 再用拖动起点夹一道：过半或轻甩就干脆利落地落到相邻那一页，永远不跳页。
private struct PagingWithTarget: ScrollTargetBehavior {
    let anchor: PagerAnchor
    let onTarget: (Int) -> Void

    func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
        ViewAlignedScrollTargetBehavior(limitBehavior: .alwaysByOne).updateTarget(&target, context: context)
        let width = context.containerSize.width
        guard width > 0 else { return }
        var page = Int((target.rect.minX / width).rounded())
        if let start = anchor.page {
            page = min(max(page, start - 1), start + 1)
        }
        target.rect.origin.x = CGFloat(page) * width
        // 这时还在布局 / 手势回调里，改状态放到下一轮
        DispatchQueue.main.async { onTarget(page) }
    }
}
