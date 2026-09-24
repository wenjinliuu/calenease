import SwiftUI

extension Color {
    /// 从 `#rrggbb` 色值构造颜色，认不出来时回落到强调蓝。
    init(hexString: String) {
        self.init(uiColor: UIColor(hexString: hexString))
    }
}

extension UIColor {
    convenience init(hexString: String) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self.init(red: 0.227, green: 0.431, blue: 0.965, alpha: 1)
            return
        }
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255,
                  green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255,
                  alpha: 1)
    }

    /// 浅色 / 深色两个色值合成一个动态颜色。
    static func dynamic(light: String, dark: String) -> UIColor {
        UIColor { $0.userInterfaceStyle == .dark ? UIColor(hexString: dark) : UIColor(hexString: light) }
    }
}

// MARK: - 色彩计算

/// OKLCH 色彩运算。
///
/// 做淡色一律在 OKLCH 里抬明度、把彩度顶在该明度下 sRGB 能给的最大值，
/// 不要用 `color.opacity(_:)` 压在白底上——那等价于和白色插值，会把彩度稀释掉，
/// 橙会变成粉橘、绿会变成灰绿。文字色同理，是同色相压暗或提亮出来的一阶，
/// 不是黑或白。
enum ColorMath {

    // MARK: sRGB ↔ OKLab

    private static func toLinear(_ v: Double) -> Double {
        v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
    }

    private static func toGamma(_ v: Double) -> Double {
        v <= 0.0031308 ? 12.92 * v : 1.055 * pow(v, 1 / 2.4) - 0.055
    }

    private static func components(_ hexString: String) -> (Double, Double, Double) {
        var text = hexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return (0, 0, 0) }
        return (Double((value >> 16) & 0xFF) / 255,
                Double((value >> 8) & 0xFF) / 255,
                Double(value & 0xFF) / 255)
    }

    private static func hexString(_ rgb: (Double, Double, Double)) -> String {
        let clamp = { (v: Double) in UInt32((max(0, min(1, v)) * 255).rounded()) }
        return String(format: "#%02x%02x%02x", clamp(rgb.0), clamp(rgb.1), clamp(rgb.2))
    }

    private static func oklab(_ rgb: (Double, Double, Double)) -> (Double, Double, Double) {
        let r = toLinear(rgb.0), g = toLinear(rgb.1), b = toLinear(rgb.2)
        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    private static func rgb(_ lab: (Double, Double, Double)) -> (Double, Double, Double) {
        let l = pow(lab.0 + 0.3963377774 * lab.1 + 0.2158037573 * lab.2, 3)
        let m = pow(lab.0 - 0.1055613458 * lab.1 - 0.0638541728 * lab.2, 3)
        let s = pow(lab.0 - 0.0894841775 * lab.1 - 1.2914855480 * lab.2, 3)
        return (toGamma(4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s),
                toGamma(-1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s),
                toGamma(-0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s))
    }

    private static func inGamut(_ c: (Double, Double, Double)) -> Bool {
        let ok = { (v: Double) in v >= -0.001 && v <= 1.001 }
        return ok(c.0) && ok(c.1) && ok(c.2)
    }

    private static func lch(_ hexString: String) -> (l: Double, c: Double, h: Double) {
        let lab = oklab(components(hexString))
        return (lab.0, (lab.1 * lab.1 + lab.2 * lab.2).squareRoot(), atan2(lab.2, lab.1))
    }

    private static func rgb(lightness: Double, chroma: Double, hue: Double) -> (Double, Double, Double) {
        rgb((lightness, chroma * cos(hue), chroma * sin(hue)))
    }

    /// 给定明度和色相时 sRGB 还装得下的最大彩度。
    private static func maxChroma(lightness: Double, hue: Double) -> Double {
        var low = 0.0, high = 0.45
        for _ in 0..<22 {
            let mid = (low + high) / 2
            if inGamut(rgb(lightness: lightness, chroma: mid, hue: hue)) { low = mid } else { high = mid }
        }
        return low
    }

    // MARK: 对外

    /// 保持相对彩度地把一个颜色移到指定明度。
    static func at(_ hexString: String, lightness target: Double) -> String {
        let base = lch(hexString)
        let ceiling = max(maxChroma(lightness: base.l, hue: base.h), 1e-6)
        let relative = min(base.c / ceiling, 1)
        let chroma = maxChroma(lightness: target, hue: base.h) * relative
        return Self.hexString(rgb(lightness: target, chroma: chroma, hue: base.h))
    }

    static func relativeLuminance(_ hexString: String) -> Double {
        let c = components(hexString)
        return 0.2126 * toLinear(c.0) + 0.7152 * toLinear(c.1) + 0.0722 * toLinear(c.2)
    }

    /// WCAG 对比度。
    static func contrast(_ a: String, _ b: String) -> Double {
        let x = relativeLuminance(a), y = relativeLuminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// 沿着同一个色相往下压，直到在这块底色上够到目标对比度为止。
    /// 压不出来（底色本身已经够暗）返回 nil。
    static func darken(_ base: String, on ground: String, target: Double) -> String? {
        var lightness = lch(ground).l
        for _ in 0..<140 {
            lightness = max(0.005, lightness - 0.004)
            let candidate = at(base, lightness: lightness)
            if contrast(candidate, ground) >= target { return candidate }
        }
        return nil
    }

    /// 沿着同一个色相走，直到在给定底色上够到目标对比度为止。
    /// 底色暗就往亮走，底色亮就往暗走；走不到就返回这一路上最好的一阶。
    static func step(_ base: String, on ground: String, target: Double = 4.5) -> String {
        let lighten = relativeLuminance(ground) < 0.30
        var lightness = lch(ground).l
        var best = base
        var bestContrast = contrast(base, ground)
        for _ in 0..<26 {
            lightness = lighten ? min(0.99, lightness + 0.035) : max(0.05, lightness - 0.035)
            let candidate = at(base, lightness: lightness)
            let value = contrast(candidate, ground)
            if value >= target { return candidate }
            if value > bestContrast { bestContrast = value; best = candidate }
        }
        return best
    }
}

// MARK: - 班次配色

/// 一个班次在日历上用到的三个颜色。
///
/// `mark` 是 13pt 色标的底色，`ink` 是色标里那个简称字，`text` 是格子底上的工时数字。
/// 深色模式把色标提亮到 OKLCH 明度 0.78 配黑字——纯黑底上放原色色标会显脏，
/// 提亮之后黑字最差也有 9.89:1。
///
/// 浅色模式填充一个像素都不动，简称字统一用白色。
struct ShiftTone {
    let mark: Color
    let ink: Color
    let text: Color
}

/// 日程用的三个颜色：`fill` 色条底，`ink` 色条上的字，`solid` 列表里的小色点、时间轴色块左边的竖线。
struct EventTone {
    let fill: Color
    let ink: Color
    let solid: Color
}

enum Tone {
    /// 深色模式下色标统一提到这个明度。
    static let darkMarkLightness = 0.78

    /// 今天那一格的整格填充。工时数字的对比度按这层底算，所以填不填都达标。
    static let todayFillLight = ColorMath.at("#007AFF", lightness: 0.93)
    static let todayFillDark = ColorMath.at("#0A84FF", lightness: 0.30)

    /// 色标里那个简称字。
    ///
    /// 浅色下一律白字。同色深字（夜班蓝配 #001C42、白班橙配 #5B3200）数值上够线，
    /// 但实际看下来白字在这批活力色上更清爽，夜班蓝尤其明显——深海军蓝压在蓝底上
    /// 反而糊成一片。整月的色标都是白字，读起来也更统一。
    static func markInk(on mark: String) -> String { "#FFFFFF" }

    // 色彩运算每次要跑几千步 OKLab 换算，日历每一格每一帧都要取色——
    // 不缓存的话左右滑动时主线程全耗在这里。色值就那么十几个，按色值记住。
    private static let cacheLock = NSLock()
    private static var shiftCache: [String: ShiftTone] = [:]
    private static var surfaceCache: [String: Color] = [:]
    private static var eventCache: [String: EventTone] = [:]

    static func shift(_ hexColor: String) -> ShiftTone {
        if let cached = cacheLock.withLock({ shiftCache[hexColor] }) { return cached }
        let markLight = hexColor
        let markDark = ColorMath.at(hexColor, lightness: darkMarkLightness)
        let tone = ShiftTone(
            mark: Color(uiColor: .dynamic(light: markLight, dark: markDark)),
            // 深色下色标提亮到 0.78，黑字最差也有 9.89:1，观感也更贴近系统控件。
            ink: Color(uiColor: .dynamic(light: markInk(on: markLight), dark: "#000000")),
            text: onSurface(hexColor)
        )
        cacheLock.withLock { shiftCache[hexColor] = tone }
        return tone
    }

    /// 直接给一个色值要压在它上面的字色。色球、循环预览的小方块、取色盘的对勾都用它——
    /// 这些地方的底是原色（不随深浅切换），所以按原色判定，不能拿动态的 `ShiftTone.ink`。
    static func ink(on hexColor: String) -> Color {
        Color(hexString: markInk(on: hexColor))
    }

    /// 日程色条：淡色底 + 同色相的深字，和统计页指标块一个路子。
    static func event(_ hexColor: String) -> EventTone {
        if let cached = cacheLock.withLock({ eventCache[hexColor] }) { return cached }
        let fillLight = ColorMath.at(hexColor, lightness: 0.9)
        let fillDark = ColorMath.at(hexColor, lightness: 0.34)
        let tone = EventTone(
            fill: Color(uiColor: .dynamic(light: fillLight, dark: fillDark)),
            ink: Color(uiColor: .dynamic(light: ColorMath.step(hexColor, on: fillLight),
                                         dark: ColorMath.step(hexColor, on: fillDark))),
            solid: Color(uiColor: .dynamic(light: hexColor, dark: ColorMath.at(hexColor, lightness: darkMarkLightness)))
        )
        cacheLock.withLock { eventCache[hexColor] = tone }
        return tone
    }

    /// 职责标签、班次名这类"压在格子底上的彩色文字"。
    static func onSurface(_ hexColor: String) -> Color {
        if let cached = cacheLock.withLock({ surfaceCache[hexColor] }) { return cached }
        let color = Color(uiColor: .dynamic(light: ColorMath.step(hexColor, on: todayFillLight),
                                            dark: ColorMath.step(hexColor, on: todayFillDark)))
        cacheLock.withLock { surfaceCache[hexColor] = color }
        return color
    }
}

// MARK: - 语义色与页面层次

/// 语义色和班次色是两组东西。
///
/// 语义色（强调、警示、成功）走系统色，深浅两套由系统给；班次色是用户自己挑的，
/// 走 `Tone` 那一套运算。两者不共用色值，这样改班次色不会连累系统控件。
enum Palette {

    // MARK: 语义色

    static let blue = Color(.systemBlue)
    static let green = Color(.systemGreen)
    static let orange = Color(.systemOrange)
    static let purple = Color(.systemPurple)
    static let pink = Color(.systemPink)
    static let yellow = Color(.systemYellow)
    static let gray = Color(.systemGray)
    static let cyan = Color(.systemCyan)
    static let red = Color(.systemRed)

    // MARK: 日历专用

    /// 放假的「休」和八个法定节日。比 systemRed 深一阶，8pt 的小字才压得住白底。
    static let holiday = Color(uiColor: .dynamic(light: "#D70015", dark: "#FF6961"))
    /// 调休上班的「班」。含义与「休」相反，用系统蓝。
    static let adjustedWorkday = Color(.systemBlue)
    /// 元宵、七夕这类传统节日：比法定节日淡一档的琥珀色，一眼分得出「不放假」。
    /// 浅色 4.6:1、深色 9.6:1，8pt 小字也看得清。
    static let traditionalFestival = Color(uiColor: .dynamic(light: "#A8651C", dark: "#E0A458"))
    /// 今天那一格的填充。
    static let todayFill = Color(uiColor: .dynamic(light: Tone.todayFillLight, dark: Tone.todayFillDark))
    /// 休息日的简称。
    static let restInk = Color(uiColor: .dynamic(light: "#6C6C70", dark: "#98989D"))

    // MARK: - 背景层次

    /// 日历、统计这类自己画的页面：纯白底，内容放在浅灰卡片里。深色是纯黑底、深灰卡片。
    static let canvas = Color(uiColor: .dynamic(light: "#FFFFFF", dark: "#000000"))
    /// 设置这类 `Form` 页面的底色。
    ///
    /// `Form` 的行底色是系统给的纯白，页底要比它暗一档分组才看得出来：
    /// #F7F7FA 对白还有 1.069 的亮度比，再白就糊成一片了。
    static let grouped = Color(uiColor: .dynamic(light: "#F7F7FA", dark: "#000000"))
    /// 卡片。白底上的浅灰块，不描边。
    static let card = Color(uiColor: .dynamic(light: "#F3F3F6", dark: "#1C1C1E"))
    /// 卡片里的内层面：指标块、输入框。浅灰卡里放白块。
    static let inset = Color(uiColor: .dynamic(light: "#FFFFFF", dark: "#2C2C2E"))
    /// 分隔线。
    static let hairline = Color(uiColor: .dynamic(light: "#E3E3E9", dark: "#38383A"))
}

extension ShiftDefinition {
    var tint: Color { Color(hexString: color) }
    var tone: ShiftTone { Tone.shift(color) }
    /// 压在 `tint` 上的字色。
    var inkOnTint: Color { Tone.ink(on: color) }
}

extension DutyTag {
    var tint: Color { Color(hexString: color) }
    /// 标签在格子里是一个没有底的彩色字，所以要取白底/黑底上达标的那一阶。
    var inkOnSurface: Color { Tone.onSurface(color) }
}
