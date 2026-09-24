import Foundation

/// 职责标签。一天可以挂多个，和主班次相互独立。
struct DutyTag: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var name: String
    var shortName: String
    var color: String
}
