import Foundation
import SwiftData

@Model
final class StoredDailyAQI {
    var day: Date
    var peakAQI: Int
    var latitude: Double
    var longitude: Double
    var fetchedAt: Date

    init(day: Date, peakAQI: Int, latitude: Double, longitude: Double, fetchedAt: Date) {
        self.day = day
        self.peakAQI = peakAQI
        self.latitude = latitude
        self.longitude = longitude
        self.fetchedAt = fetchedAt
    }
}
