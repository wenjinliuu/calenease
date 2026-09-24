import SwiftUI
import UIKit

/// 只认横向的拖动。竖向滚动要等它先放弃，所以竖着滑页面一点不受影响。
///
/// 月历翻页、日程左滑、周视图换周都用它。不用 SwiftUI 的 `DragGesture`：
/// 它挂在滚动视图里的内容上时（哪怕是 simultaneousGesture），手指落在那块内容上
/// 竖向滚动就会被它抢走——事项页手指按在日程上滑不动就是这个原因。
struct HorizontalPan: UIGestureRecognizerRepresentable {
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
