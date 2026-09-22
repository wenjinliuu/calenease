import SwiftUI

/// 点月份标题弹出来的选择器。日历页和统计页共用。
///
/// 按月：上面一行切年份，下面 12 个月平铺，点一下就跳过去。
/// 按年度：一页 12 个年度，左右翻页。综合工时制的年度不一定从 1 月开始，
/// 这时每个年份下面标一行「3 月起」。
struct PeriodPickerSheet: View {
    enum Mode { case month, year }

    let mode: Mode
    /// 当前查看的年月（月为零基）。按年度时 `selectedYear` 是年度起始的那一年。
    let selectedYear: Int
    let selectedMonth: Int
    let currentYear: Int
    let currentMonth: Int
    /// 年度起始月，一基。
    var annualStartMonth: Int = 1
    /// 选中后回调年与零基月。
    let onPick: (_ year: Int, _ month: Int) -> Void

    @Environment(\.dismiss) private var dismiss
    /// 按月时是正在看的年份；按年度时是这一页第一个年份。
    @State private var pageYear: Int
    @State private var pushEdge: Edge = .trailing

    init(mode: Mode,
         selectedYear: Int,
         selectedMonth: Int,
         currentYear: Int,
         currentMonth: Int,
         annualStartMonth: Int = 1,
         onPick: @escaping (_ year: Int, _ month: Int) -> Void) {
        self.mode = mode
        self.selectedYear = selectedYear
        self.selectedMonth = selectedMonth
        self.currentYear = currentYear
        self.currentMonth = currentMonth
        self.annualStartMonth = annualStartMonth
        self.onPick = onPick
        _pageYear = State(initialValue: mode == .month ? selectedYear : selectedYear - 4)
    }

    private var step: Int { mode == .month ? 1 : 12 }

    private var title: String {
        mode == .month ? "\(pageYear)年" : "\(pageYear)–\(pageYear + 11)"
    }

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 8) {
                Button { turn(-1) } label: {
                    Image(systemName: "chevron.left").font(.footnote.weight(.bold))
                }
                .buttonStyle(SecondaryButton())
                .accessibilityLabel(mode == .month ? "上一年" : "往前")

                Text(title)
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)

                Button { turn(1) } label: {
                    Image(systemName: "chevron.right").font(.footnote.weight(.bold))
                }
                .buttonStyle(SecondaryButton())
                .accessibilityLabel(mode == .month ? "下一年" : "往后")
            }

            grid
                .id(pageYear)
                .transition(.asymmetric(
                    insertion: .move(edge: pushEdge).combined(with: .opacity),
                    removal: .move(edge: pushEdge == .trailing ? .leading : .trailing).combined(with: .opacity)))
                .frame(maxWidth: .infinity)
                .clipped()

            Button(mode == .month ? "回到本月" : "回到本年度") {
                pick(year: currentYear, month: mode == .month ? currentMonth : annualStartMonth - 1)
            }
            .font(.subheadline.weight(.semibold))
            .buttonStyle(SecondaryButton(tint: Palette.green))
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .presentationDetents([.height(mode == .month ? 330 : 350)])
        .presentationDragIndicator(.visible)
    }

    private var grid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: mode == .month ? 4 : 3),
                  spacing: 10) {
            if mode == .month {
                ForEach(0..<12, id: \.self) { month in
                    cell(title: "\(month + 1)月",
                         caption: nil,
                         isSelected: pageYear == selectedYear && month == selectedMonth,
                         isCurrent: pageYear == currentYear && month == currentMonth) {
                        pick(year: pageYear, month: month)
                    }
                }
            } else {
                ForEach(pageYear..<(pageYear + 12), id: \.self) { year in
                    cell(title: "\(String(year))年",
                         caption: annualStartMonth == 1 ? nil : "\(annualStartMonth)月起",
                         isSelected: year == selectedYear,
                         isCurrent: year == currentYear) {
                        pick(year: year, month: annualStartMonth - 1)
                    }
                }
            }
        }
    }

    private func cell(title: String,
                      caption: String?,
                      isSelected: Bool,
                      isCurrent: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(isSelected || isCurrent ? .bold : .medium))
                    .monospacedDigit()
                if let caption {
                    Text(caption)
                        .font(.caption2)
                        .opacity(0.75)
                }
            }
            .foregroundStyle(isSelected ? AnyShapeStyle(.white)
                             : isCurrent ? AnyShapeStyle(Palette.blue) : AnyShapeStyle(.primary))
            .frame(maxWidth: .infinity)
            .frame(height: caption == nil ? 44 : 50)
            .background(isSelected ? Palette.blue : Palette.inset,
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func turn(_ direction: Int) {
        pushEdge = direction > 0 ? .trailing : .leading
        withAnimation(.smooth(duration: 0.3)) { pageYear += direction * step }
    }

    private func pick(year: Int, month: Int) {
        onPick(year, month)
        dismiss()
    }
}
