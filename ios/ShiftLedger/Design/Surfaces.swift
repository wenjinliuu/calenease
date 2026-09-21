import SwiftUI

/// 卡片与浮层的统一封装。
///
/// 页面是纯灰底，内容分成「底 → 卡片 → 格子」三层，靠系统分组背景色拉开层次，
/// 而不是靠阴影堆叠。玻璃材质只留给真正浮在内容之上的东西（轻提示、悬浮控件），
/// 纯色背景下大面积玻璃没有可折射的内容，只会显脏。
extension View {

    /// 页面底色。`Form` 默认那层分组灰要先隐掉，否则盖不住。
    func pageBackground() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Palette.canvas)
    }

    /// 卡片：日历页的浮层、统计卡、分组容器。
    ///
    /// 页面是近白、卡片是纯白，两者只差 4% 亮度，所以边界交给描边。
    /// 不用阴影——近白底上的阴影会脏，描边干净得多。
    func card(cornerRadius: CGFloat = 22, padding: CGFloat = 16) -> some View {
        self
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Palette.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Palette.cardStroke, lineWidth: 1)
            }
    }

    /// 卡片里的内层面：日历格、指标块。
    func insetSurface(cornerRadius: CGFloat = 14, tint: Color? = nil) -> some View {
        background(
            (tint.map { $0.opacity(0.12) } ?? Palette.inset),
            in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        )
    }

    /// 浮在内容之上的胶囊：轻提示、悬浮控件。
    func floatingPill(tint: Color? = nil, interactive: Bool = true) -> some View {
        glassEffect(GlassStyle.pill(tint: tint, interactive: interactive), in: Capsule())
    }
}

/// Glass 配置的集中定义。iOS 26 的 Liquid Glass 系统 API 只出现在这个文件里。
enum GlassStyle {
    static func pill(tint: Color?, interactive: Bool) -> Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.22)) }
        if interactive { glass = glass.interactive() }
        return glass
    }
}

/// 主操作按钮。
struct ProminentButton: ButtonStyle {
    var tint: Color = Palette.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            // 按下即反馈，临界阻尼、不过冲
            .animation(.spring(response: 0.3, dampingFraction: 1), value: configuration.isPressed)
    }
}

/// 次级操作按钮：淡色底 + 强调色文字。
struct SecondaryButton: ButtonStyle {
    var tint: Color = Palette.blue

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(tint.opacity(configuration.isPressed ? 0.24 : 0.14), in: Capsule())
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 1), value: configuration.isPressed)
    }
}

/// 分区标题。
struct SectionHeader: View {
    let title: String
    var eyebrow: String?
    var badge: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                if let eyebrow {
                    Text(eyebrow)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Text(title).font(.headline)
            }
            Spacer(minLength: 12)
            if let badge {
                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Palette.inset, in: Capsule())
            }
        }
    }
}

/// 统计数字块。
struct MetricTile: View {
    let label: String
    let value: String
    var detail: String?
    var tint: Color = Palette.blue
    var symbol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                if let symbol {
                    Image(systemName: symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(tint)
                }
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title2.weight(.bold))
                .foregroundStyle(tint)
                .contentTransition(.numericText())
                .monospacedDigit()
            if let detail {
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(13)
        .insetSurface(cornerRadius: 16, tint: tint)
    }
}

/// 班次色球。
struct ShiftOrb: View {
    let shift: ShiftDefinition
    var size: CGFloat = 38

    var body: some View {
        Text(shift.shortName)
            .font(.system(size: size * 0.38, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .padding(.horizontal, 2)
            .frame(width: size, height: size)
            .background(shift.tint, in: Circle())
    }
}

/// 标签小胶囊。
struct TagChip: View {
    let tag: DutyTag
    var body: some View {
        Text(tag.shortName)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tag.tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tag.tint.opacity(0.16), in: Capsule())
    }
}
