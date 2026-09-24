import Foundation

/// 循环模板的分类，决定职业预设推荐哪些模板。
enum CycleCategory: String, Codable, Sendable, CaseIterable {
    case manufacturing
    case threeShift
    case medical
    case custom

    var label: String {
        switch self {
        case .manufacturing: "两班倒"
        case .threeShift: "三班倒"
        case .medical: "医护"
        case .custom: "自定义"
        }
    }
}

/// 循环模板：保存的是班次 ID 序列，因此可以用任意自定义班次。
struct CycleTemplate: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var caption: String
    var shiftIds: [String]
    var category: CycleCategory
    var builtIn: Bool

    init(id: String,
         name: String,
         caption: String = "",
         shiftIds: [String],
         category: CycleCategory = .manufacturing,
         builtIn: Bool = false) {
        self.id = id
        self.name = name
        self.caption = caption
        self.shiftIds = shiftIds
        self.category = category
        self.builtIn = builtIn
    }

    var lengthLabel: String { "\(shiftIds.count) 天一轮" }
}

/// 当前生效的循环：从 `startDate` 起按 `shiftIds` 无限重复。
struct ActiveCycle: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    /// "yyyy-MM-dd"
    var startDate: String
    var shiftIds: [String]
}
