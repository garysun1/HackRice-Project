import Foundation

public protocol AirQualityHistoryService: Sendable {
    /// Daily peak US AQI keyed by startOfDay (in `calendar`), covering the last `days` days up to today.
    func dailyPeakAQI(
        latitude: Double,
        longitude: Double,
        days: Int,
        calendar: Calendar
    ) async throws -> [Date: Int]
}

public struct OpenMeteoAirQualityHistory: AirQualityHistoryService {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func dailyPeakAQI(
        latitude: Double,
        longitude: Double,
        days: Int,
        calendar: Calendar
    ) async throws -> [Date: Int] {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "hourly", value: "us_aqi"),
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "past_days", value: String(days)),
            URLQueryItem(name: "forecast_days", value: "1")
        ]
        let (data, _) = try await session.data(from: components.url!)
        let response = try JSONDecoder().decode(Response.self, from: data)
        return AirQualityHistory.dailyPeaks(
            hourlyTimes: response.hourly.time,
            values: response.hourly.us_aqi,
            calendar: calendar
        )
    }

    private struct Response: Decodable {
        struct Hourly: Decodable {
            let time: [String]
            let us_aqi: [Int?]
        }

        let hourly: Hourly
    }
}

public struct CannedAirQualityHistory: AirQualityHistoryService {
    private let peaks: [Date: Int]

    public init(peaks: [Date: Int]) {
        self.peaks = peaks
    }

    public func dailyPeakAQI(
        latitude: Double,
        longitude: Double,
        days: Int,
        calendar: Calendar
    ) async throws -> [Date: Int] {
        Dictionary(
            peaks.map { (calendar.startOfDay(for: $0.key), $0.value) },
            uniquingKeysWith: { _, last in last }
        )
    }
}

public enum AirQualityHistory {
    /// Buckets local-time hourly strings into daily maximum AQI values; nil hours and empty days are omitted.
    public static func dailyPeaks(
        hourlyTimes: [String],
        values: [Int?],
        calendar: Calendar
    ) -> [Date: Int] {
        var peaks: [Date: Int] = [:]
        for (time, value) in zip(hourlyTimes, values) {
            guard let value else { continue }
            let components = time.prefix(10).split(separator: "-").compactMap { Int($0) }
            guard components.count == 3,
                  let day = calendar.date(from: DateComponents(
                    year: components[0],
                    month: components[1],
                    day: components[2]
                  )) else { continue }
            let dayStart = calendar.startOfDay(for: day)
            peaks[dayStart] = max(peaks[dayStart] ?? value, value)
        }
        return peaks
    }
}
