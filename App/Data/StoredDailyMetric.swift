import Foundation
import SwiftData

@Model
final class StoredDailyMetric {
    var id: UUID
    var day: Date
    var kindRaw: String
    var value: Double

    init(id: UUID = UUID(), day: Date, kindRaw: String, value: Double) {
        self.id = id
        self.day = day
        self.kindRaw = kindRaw
        self.value = value
    }
}
