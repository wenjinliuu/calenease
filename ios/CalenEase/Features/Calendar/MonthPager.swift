import Observation
import SwiftUI

/// 月历翻页器：三张月历卡片（上个月、这个月、下个月）并排，手指拖着走。
///
/// 松手时按「手指甩出去之后会停在哪」来判断（Apple 的动量投影：当前位移 + 速度折算的惯性距离），
/// 投影越过三分之一页就翻，否则弹回。翻页的弹簧不回弹，并且接着手指松开时的速度继续走，
/// 拖动和动画之间没有停顿的接缝。一次永远只翻一个月。
///
/// 手指底下每一帧只改一个数：`PagerDrag.x`。读它的只有最里层的 `PagerTrack`，
/// 它的 body 只有一个 offset——三张月历、外面整页都不会因为拖动重算或重新排版。
/// 高度也不在拖动时插值（那样每一帧都要把下面整页重新排一遍）：月份变了时跟着同一条弹簧变一次。
///
/// 切月的时机：松手判定要翻页的那一刻就把月份交给 store，同时把位移加上一整页宽度，
/// 画面位置不变；然后只把位移动画归零。月份标题立刻跟上，卡片接着滑完。
/// 翻到别的月不改选中的日子——用户自己点了才算选。
struct MonthPager: View {
    @Environment(ScheduleStore.self) private var store

    let batchMode: Bool
    let selectedDates: Set<String>
    let selectedDay: String?
    let onSelect: (String) -> Void

    @State private var drag = PagerDrag()
    @State private var width: CGFloat = 0
    /// 当前显示的行数（5 或 6）。只在月份变了的时候跟着动画变一次。
    @State private var rows: Int

    init(focusedIndex: Int,
         batchMode: Bool,
         selectedDates: Set<String>,
         selectedDay: String?,
         onSelect: @escaping (String) -> Void) {
        self.batchMode = batchMode
        self.selectedDates = selectedDates
        self.selectedDay = selectedDay
        self.onSelect = onSelect
        _rows = State(initialValue: CalendarMonthGrid.rows(index: focusedIndex))
    }

    /// 多选时每格底下挂一枚勾，落在行距里；最后一行的勾要多留这点地方。
    private var bottomSlack: CGFloat { batchMode ? 10 : 0 }

    /// Apple「Designing Fluid Interfaces」里的惯性投影：松手后按系统滚动的减速率还能滑多远。
    static func projection(velocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
        velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    static let settle = Animation.spring(duration: 0.32, bounce: 0)

    var body: some View {
        let document = store.document
        let layout = CellLayout(document: document)
        let index = store.focusedIndex
        let pageWidth = max(width, 1)
        let contentHeight = CalendarMonthGrid.height(rows: 6, layout: layout) + bottomSlack

        PagerTrack(drag: drag, pageWidth: pageWidth) {
            HStack(alignment: .top, spacing: 0) {
                ForEach([index - 1, index, index + 1], id: \.self) { page in
                    CalendarMonthGrid(year: page / 12,
                                      month: page % 12,
                                      document: document,
                                      todayKey: store.todayKey,
                                      batchMode: batchMode,
                                      selectedDates: selectedDates,
                                      holidays: store.holidays,
                                      selectedDay: selectedDay.flatMap { day in
                                          day.hasPrefix(ScheduleCalendar.monthKey(year: page / 12, month: page % 12)) ? day : nil
                                      },
                                      onSelect: onSelect)
                        .equatable()
                        .frame(width: pageWidth, height: contentHeight, alignment: .top)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: CalendarMonthGrid.height(rows: CGFloat(rows), layout: layout) + bottomSlack, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(HorizontalPan(onChange: { translation in
            drag.x = translation
        }, onEnd: { translation, velocity in
            finish(translation: translation, velocity: velocity, index: index)
        }))
        .onChange(of: index) { _, newIndex in
            // 翻页、按钮、月份选择器、统计页改了月份：高度跟着同一条弹簧变过去
            let target = CalendarMonthGrid.rows(index: newIndex)
            if rows != target { withAnimation(Self.settle) { rows = target } }
        }
    }

    private func finish(translation: CGFloat, velocity: CGFloat, index: Int) {
        guard width > 0 else { drag.x = 0; return }
        let projected = translation + Self.projection(velocity: velocity)
        let threshold = width / 3
        let step = projected < -threshold ? 1 : projected > threshold ? -1 : 0

        if step != 0 {
            // 月份立刻交出去；位移同时补上一整页，画面停在原处不跳
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.focus(index: index + step)
                drag.x += CGFloat(step) * width
            }
        }
        // 接着手指的速度走：弹簧的初速度按「离目标还剩多远」归一化
        let remaining = -drag.x
        let relative = abs(remaining) > 1 ? velocity / remaining : 0
        withAnimation(.interpolatingSpring(duration: 0.32, bounce: 0,
                                           initialVelocity: min(max(relative, 0), 12))) {
            drag.x = 0
        }
    }
}

/// 拖动位移。单独放一个对象里，只有 `PagerTrack` 读它。
@Observable
final class PagerDrag {
    var x: CGFloat = 0
}

/// 三张月历排成一条，按位移整体平移。拖动时只有这里的 body 每帧重算，而它只有一个 offset。
private struct PagerTrack<Content: View>: View {
    let drag: PagerDrag
    let pageWidth: CGFloat
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(width: pageWidth * 3, alignment: .leading)
            .offset(x: -pageWidth + drag.x)
    }
}
