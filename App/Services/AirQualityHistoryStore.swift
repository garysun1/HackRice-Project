import Foundation
import SwiftData
import CoreLocation
import OSLog
import HealthCore

@MainActor
final class AirQualityHistoryStore {
    private static let log = Logger(subsystem: "com.hackrice.healthapp", category: "air-quality")
    private let context: ModelContext
    private let service: any AirQualityHistoryService
    private let location: LocationService
    private let calendar: Calendar
    private var isRefreshing = false

    init(
        context: ModelContext,
        service: any AirQualityHistoryService,
        location: LocationService,
        calendar: Calendar = .current
    ) {
        self.context = context
        self.service = service
        self.location = location
        self.calendar = calendar
    }

    var rowCount: Int {
        (try? context.fetchCount(FetchDescriptor<StoredDailyAQI>())) ?? 0
    }

    func refreshIfStale(days: Int = 92) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let coordinate = await location.currentCoordinate()
        var newestDescriptor = FetchDescriptor<StoredDailyAQI>(
            sortBy: [SortDescriptor(\.fetchedAt, order: .reverse)]
        )
        newestDescriptor.fetchLimit = 1
        if let newest = try? context.fetch(newestDescriptor).first,
           Date().timeIntervalSince(newest.fetchedAt) < 6 * 60 * 60,
           Self.distance(
            from: CLLocationCoordinate2D(latitude: newest.latitude, longitude: newest.longitude),
            to: coordinate
           ) < 25 {
            return
        }

        do {
            let peaks = try await service.dailyPeakAQI(
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                days: days,
                calendar: calendar
            )
            let fetchedAt = Date()
            let existing = (try? context.fetch(FetchDescriptor<StoredDailyAQI>())) ?? []
            var byDay = Dictionary(
                existing.map { (calendar.startOfDay(for: $0.day), $0) },
                uniquingKeysWith: { first, duplicate in
                    context.delete(duplicate)
                    return first
                }
            )
            for (day, peakAQI) in peaks {
                let day = calendar.startOfDay(for: day)
                if let stored = byDay[day] {
                    stored.peakAQI = peakAQI
                    stored.latitude = coordinate.latitude
                    stored.longitude = coordinate.longitude
                    stored.fetchedAt = fetchedAt
                } else {
                    let stored = StoredDailyAQI(
                        day: day,
                        peakAQI: peakAQI,
                        latitude: coordinate.latitude,
                        longitude: coordinate.longitude,
                        fetchedAt: fetchedAt
                    )
                    context.insert(stored)
                    byDay[day] = stored
                }
            }
            try? context.save()
        } catch {
            Self.log.error("AQI history refresh failed: \(error.localizedDescription)")
        }
    }

    func peaks(from start: Date, to end: Date) -> [Date: Int] {
        let descriptor = FetchDescriptor<StoredDailyAQI>(
            predicate: #Predicate { $0.day >= start && $0.day <= end }
        )
        return Dictionary(
            ((try? context.fetch(descriptor)) ?? []).map {
                (calendar.startOfDay(for: $0.day), $0.peakAQI)
            },
            uniquingKeysWith: { _, last in last }
        )
    }

    private static func distance(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D
    ) -> Double {
        let earthRadius = 6_371.0
        let latitudeDelta = (to.latitude - from.latitude) * .pi / 180
        let longitudeDelta = (to.longitude - from.longitude) * .pi / 180
        let firstLatitude = from.latitude * .pi / 180
        let secondLatitude = to.latitude * .pi / 180
        let a = sin(latitudeDelta / 2) * sin(latitudeDelta / 2)
            + cos(firstLatitude) * cos(secondLatitude)
            * sin(longitudeDelta / 2) * sin(longitudeDelta / 2)
        return earthRadius * 2 * atan2(sqrt(a), sqrt(1 - a))
    }
}
