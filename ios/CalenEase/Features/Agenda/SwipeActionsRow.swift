import SwiftUI

/// 左滑露出「编辑」「删除」两颗按钮；一直滑过大半直接删。只认横向拖动，竖着滑照常滚动。
///
/// 事项页日视图的日程、日历页当天面板里的日程都用它。
/// 横向拖动一开始，里面的内容就不再接收点按：否则手指松开时，条目里的按钮会把这次拖动
/// 当成一次点击。往右拖也拦住（往右没有操作）。已经滑开的一条，点它只是合上。
///
/// 拖动用 UIKit 的横向手势（`HorizontalPan`）：竖着滑时它立刻放弃，列表照常滚动。
/// 之前用 SwiftUI 的 DragGesture，手指落在日程上时整个列表都滑不动。
struct SwipeActionsRow<Content: View>: View {
    let id: String
    @Binding var openRow: String?
    let onEdit: () -> Void
    let onDelete: () -> Void
    var cornerRadius: CGFloat = 16
    @ViewBuilder let content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var startOffset: CGFloat = 0
    @State private var dragging = false

    private static var buttonWidth: CGFloat { 68 }
    private static var revealWidth: CGFloat { buttonWidth * 2 + 6 }

    var body: some View {
        content()
            // 拖动中、或者已经滑开时，内容不接点按
            .allowsHitTesting(!dragging && offset == 0)
            .offset(x: offset)
            .overlay {
                if offset < 0 && !dragging {
                    Color.clear
                        .contentShape(Rectangle())
                        .offset(x: offset)
                        .onTapGesture { withAnimation(.snappy(duration: 0.22)) { close() } }
                }
            }
            .background(alignment: .trailing) { actions }
            // 只裁左右：事项时间线上胶囊之间的连线要伸到下一条，上下不能裁
            .mask { Rectangle().padding(.vertical, -400) }
            // 内容暂时不接点按时，拖动手势也要有地方落手
            .contentShape(Rectangle())
            .gesture(HorizontalPan(onChange: dragChanged, onEnd: dragEnded))
            .onChange(of: openRow) { _, row in
                if row != id, offset != 0 { withAnimation(.snappy(duration: 0.22)) { offset = 0 } }
            }
            .accessibilityAction(named: "编辑") { onEdit() }
            .accessibilityAction(named: "删除") { onDelete() }
    }

    private var actions: some View {
        let reveal = max(0, -offset)
        // 两颗按钮按露出来的宽度平分；滑过头时删除按钮独占
        let deleteOnly = reveal > Self.revealWidth + 40
        return HStack(spacing: 6) {
            if !deleteOnly {
                actionButton("编辑", symbol: "pencil", color: Palette.blue) {
                    withAnimation(.snappy(duration: 0.22)) { close() }
                    onEdit()
                }
            }
            actionButton("删除", symbol: "trash.fill", color: Palette.red) {
                withAnimation(.snappy(duration: 0.22)) { close() }
                onDelete()
            }
        }
        .frame(width: max(0, reveal - 6))
        .padding(.vertical, 4)
        .opacity(reveal > 12 ? 1 : 0)
        .animation(.snappy(duration: 0.2), value: deleteOnly)
    }

    private func actionButton(_ title: String, symbol: String, color: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
                Text(title).font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(color, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityHidden(true)
    }

    private func dragChanged(_ dx: CGFloat) {
        if !dragging {
            dragging = true
            startOffset = offset
            if openRow != id { openRow = id }
        }
        // 往右最多回到 0，再往右只给一点阻尼
        let proposed = startOffset + dx
        offset = proposed > 0 ? min(12, proposed * 0.15) : proposed
    }

    private func dragEnded(_ dx: CGFloat, _ velocity: CGFloat) {
                guard dragging else { return }
                // 松手时按速度往前推一段，轻轻一甩也能滑开
                let predicted = dx + velocity * 0.2
                var deleteNow = false
                withAnimation(.snappy(duration: 0.25)) {
                    if offset < -(Self.revealWidth + 120) || predicted < -520 {
                        offset = -700
                        deleteNow = true
                    } else if offset < -Self.revealWidth / 2 || (predicted < -120 && offset < 0) {
                        offset = -Self.revealWidth
                        openRow = id
                    } else {
                        close()
                    }
                }
                // 松手这一帧还算在拖动里，下一帧再放开点按，免得松手本身被当成一次点击
                DispatchQueue.main.async { dragging = false }
                if deleteNow {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        onDelete()
                        offset = 0
                        if openRow == id { openRow = nil }
                    }
                }
    }

    private func close() {
        offset = 0
        if openRow == id { openRow = nil }
    }
}
