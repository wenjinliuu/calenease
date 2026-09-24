import SwiftUI
import UIKit

/// 月历翻页器：三张月历卡片（上个月、这个月、下个月）并排，手指拖着走。
///
/// 松手时按「手指甩出去之后会停在哪」来判断（Apple 的动量投影：当前位移 + 速度折算的惯性距离），
/// 投影越过三分之一页就翻，否则弹回。翻页的弹簧不回弹，并且接着手指松开时的速度继续走，
/// 拖动和动画之间没有停顿的接缝。一次永远只翻一个月。
///
/// 之前用的是分页 `ScrollView`：惯性由系统决定，甩快了会越过一个月，减速阶段又拖得很长，
/// 怎么调参数都不利落。现在位置完全由这里的 `drag` 决定，动画只有一段，行为是确定的。
///
/// 切月的时机：松手判定要翻页的那一刻就把月份交给 store，同时把 `drag` 加上一整页宽度，
/// 画面位置不变；然后只把 `drag` 动画归零。月份标题、选中的日子立刻跟上，卡片接着滑完。
///
/// 横向拖动用 UIKit 的 `UIPanGestureRecognizer`：只有横向速度占优时才开始，
/// 并且外层竖向滚动要等它先放弃——竖着滑页面、横着翻月份，互不抢手势。
struct MonthPager: View {
    @Environment(ScheduleStore.self) private var store

    let batchMode: Bool
    let selectedDates: Set<String>
    let selectedDay: String?
    let onSelect: (String) -> Void

    /// 手指拖出去的距离（正数往右，看上个月）。
    @State private var drag: CGFloat = 0
    @State private var width: CGFloat = 0

    init(focusedIndex _: Int,
         batchMode: Bool,
         selectedDates: Set<String>,
         selectedDay: String?,
         onSelect: @escaping (String) -> Void) {
        self.batchMode = batchMode
        self.selectedDates = selectedDates
        self.selectedDay = selectedDay
        self.onSelect = onSelect
    }

    /// 多选时每格底下挂一枚勾，落在行距里；最后一行的勾要多留这点地方。
    private var bottomSlack: CGFloat { batchMode ? 10 : 0 }

    /// Apple「Designing Fluid Interfaces」里的惯性投影：松手后按系统滚动的减速率还能滑多远。
    static func projection(velocity: CGFloat, decelerationRate: CGFloat = 0.998) -> CGFloat {
        velocity / 1000 * decelerationRate / (1 - decelerationRate)
    }

    var body: some View {
        let document = store.document
        let layout = CellLayout(document: document)
        let index = store.focusedIndex
        let pageWidth = max(width, 1)

        ZStack(alignment: .topLeading) {
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
                    .frame(width: pageWidth, alignment: .top)
                    .offset(x: CGFloat(page - index) * pageWidth + drag)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: height(index: index, layout: layout) + bottomSlack, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .gesture(HorizontalPan(onChange: { translation in
            drag = translation
        }, onEnd: { translation, velocity in
            finish(translation: translation, velocity: velocity, index: index)
        }))
    }

    /// 高度跟着拖动在两个月的行数之间插值（5 行 ↔ 6 行），拖到一半就是一半。
    private func height(index: Int, layout: CellLayout) -> CGFloat {
        let current = CGFloat(CalendarMonthGrid.rows(index: index))
        guard width > 0, drag != 0 else { return CalendarMonthGrid.height(rows: current, layout: layout) }
        let neighbor = CGFloat(CalendarMonthGrid.rows(index: drag < 0 ? index + 1 : index - 1))
        let progress = min(1, abs(drag) / width)
        return CalendarMonthGrid.height(rows: current + (neighbor - current) * progress, layout: layout)
    }

    private func finish(translation: CGFloat, velocity: CGFloat, index: Int) {
        guard width > 0 else { drag = 0; return }
        let projected = translation + Self.projection(velocity: velocity)
        let threshold = width / 3
        let step = projected < -threshold ? 1 : projected > threshold ? -1 : 0

        if step != 0 {
            // 月份立刻交出去；drag 同时补上一整页，画面停在原处不跳
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.focus(index: index + step)
                drag += CGFloat(step) * width
            }
        }
        // 接着手指的速度走：弹簧的初速度按「离目标还剩多远」归一化
        let remaining = -drag
        let relative = abs(remaining) > 1 ? velocity / remaining : 0
        withAnimation(.interpolatingSpring(duration: 0.32, bounce: 0,
                                           initialVelocity: min(max(relative, 0), 12))) {
            drag = 0
        }
    }
}

/// 只认横向的拖动。竖向滚动要等它先放弃，所以竖着滑页面一点不受影响。
private struct HorizontalPan: UIGestureRecognizerRepresentable {
    let onChange: (CGFloat) -> Void
    let onEnd: (CGFloat, CGFloat) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator { Coordinator() }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.delegate = context.coordinator
        recognizer.maximumNumberOfTouches = 1
        return recognizer
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChange(translation)
        case .ended:
            onEnd(translation, recognizer.velocity(in: recognizer.view).x)
        case .cancelled, .failed:
            onEnd(0, 0)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        /// 横向速度明显大于竖向才开始。
        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
            let velocity = pan.velocity(in: pan.view)
            return abs(velocity.x) > abs(velocity.y) * 1.2
        }

        /// 外层滚动视图的拖动要等翻页手势先放弃：横着拖时页面不会跟着上下晃。
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldBeRequiredToFailBy otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            otherGestureRecognizer.view is UIScrollView && otherGestureRecognizer is UIPanGestureRecognizer
        }
    }
}
