import SwiftUI

/// 月历翻页器。
///
/// 用系统的分页 `ScrollView` 做：手指拖动时由系统滚动引擎直接驱动，跟手、带惯性，
/// 相邻的月份从卡片边缘一起滑进来，拖到一半就能看见下个月。
///
/// 原来的做法是手势里改一个 offset 状态，每一帧都让整个日历页（连同下面的本月概览）
/// 重算一遍，前后月份也要等松手才出现——这就是左右滑动卡的原因。现在滑动过程中
/// 只有这个翻页器自己在更新，月历网格是 `Equatable` 的，数据没变就不重画。
///
/// 两个月行数不一样（5 行 / 6 行）时，高度按滑动进度在两者之间插值，
/// 下面的卡片跟着平滑让位，不会松手时才跳一下。
struct MonthPager: View {
    @Environment(ScheduleStore.self) private var store

    let batchMode: Bool
    let selectedDates: Set<String>
    let onSelect: (String) -> Void

    @State private var position: Int?
    /// 滑动进度，按 `range` 里的页码算，带小数。
    @State private var page: CGFloat

    init(focusedIndex: Int,
         batchMode: Bool,
         selectedDates: Set<String>,
         onSelect: @escaping (String) -> Void) {
        self.batchMode = batchMode
        self.selectedDates = selectedDates
        self.onSelect = onSelect
        _position = State(initialValue: focusedIndex)
        _page = State(initialValue: CGFloat(focusedIndex - Self.range.lowerBound))
    }

    /// 前后各五十年，足够翻。`LazyHStack` 只建看得见的那两三页。
    static let range: ClosedRange<Int> = {
        let parts = ScheduleCalendar.calendar.dateComponents([.year, .month], from: Date())
        let current = (parts.year ?? 2026) * 12 + (parts.month ?? 1) - 1
        return (current - 600)...(current + 600)
    }()

    /// 多选时每格底下挂一枚勾，落在行距里；最后一行的勾要多留这点地方。
    private var bottomSlack: CGFloat { batchMode ? 10 : 0 }

    var body: some View {
        let document = store.document
        let todayKey = store.todayKey
        let height = pagerHeight(display: document.display)

        ScrollView(.horizontal) {
            LazyHStack(alignment: .top, spacing: 0) {
                ForEach(Self.range, id: \.self) { index in
                    CalendarMonthGrid(year: index / 12,
                                      month: index % 12,
                                      document: document,
                                      todayKey: todayKey,
                                      batchMode: batchMode,
                                      selectedDates: selectedDates,
                                      onSelect: onSelect)
                        .equatable()
                        .frame(height: height, alignment: .top)
                        .containerRelativeFrame(.horizontal)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.containerSize.width > 0 ? geometry.contentOffset.x / geometry.containerSize.width : 0
        } action: { _, newValue in
            page = newValue
        }
        .onScrollPhaseChange { _, phase in
            // 停稳了再把月份交给 store。拖到一半就切的话，整页的本月概览会在手指底下重算。
            guard phase == .idle, let position, position != store.focusedIndex else { return }
            withAnimation(.snappy(duration: 0.3)) { store.focus(index: position) }
        }
        .onChange(of: store.focusedIndex) { _, target in
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
        .frame(height: height)
    }

    private func pagerHeight(display: CalendarDisplaySettings) -> CGFloat {
        let lower = page.rounded(.down)
        let fraction = page - lower
        let index = Self.range.lowerBound + Int(lower)
        let first = monthHeight(index, display: display)
        guard fraction > 0.001 else { return first + bottomSlack }
        let second = monthHeight(index + 1, display: display)
        return first + (second - first) * fraction + bottomSlack
    }

    private func monthHeight(_ index: Int, display: CalendarDisplaySettings) -> CGFloat {
        CalendarMonthGrid.height(year: index / 12, month: index % 12, display: display)
    }
}
