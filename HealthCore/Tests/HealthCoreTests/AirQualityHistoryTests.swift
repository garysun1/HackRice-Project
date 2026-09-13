import Foundation
import Testing
@testable import HealthCore

@Suite struct AirQualityHistoryTests {
    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Chicago")!
        return calendar
    }

    @Test func dailyPeaksBucketAtMidnightAndTakeMaximum() throws {
        let peaks = AirQualityHistory.dailyPeaks(
            hourlyTimes: [
                "2026-09-12T22:00",
                "2026-09-12T23:00",
                "2026-09-13T00:00",
                "2026-09-13T01:00"
            ],
            values: [70, 120, 55, 80],
            calendar: calendar
        )
        let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 12)))
        let second = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))

        #expect(peaks[calendar.startOfDay(for: first)] == 120)
        #expect(peaks[calendar.startOfDay(for: second)] == 80)
        #expect(peaks.count == 2)
    }

    @Test func nilHoursAndAllNilDaysAreOmitted() throws {
        let peaks = AirQualityHistory.dailyPeaks(
            hourlyTimes: [
                "2026-09-12T23:00",
                "2026-09-13T00:00",
                "2026-09-13T01:00"
            ],
            values: [90, nil, nil],
            calendar: calendar
        )
        let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 12)))
        let second = try #require(calendar.date(from: DateComponents(year: 2026, month: 9, day: 13)))

        #expect(peaks[calendar.startOfDay(for: first)] == 90)
        #expect(peaks[calendar.startOfDay(for: second)] == nil)
        #expect(peaks.count == 1)
    }

    @Test func cannedHistoryReturnsItsMap() async throws {
        let day = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_760_000_000))
        let expected = [day: 112]
        let service = CannedAirQualityHistory(peaks: expected)
        let result = try await service.dailyPeakAQI(
            latitude: 0,
            longitude: 0,
            days: 92,
            calendar: calendar
        )

        #expect(result == expected)
    }
}
