import Foundation

/// Environmental context captured at the moment a health event is recorded.
public struct EnvironmentSnapshot: Codable, Hashable, Sendable {
    /// US AQI (0–500).
    public var aqi: Int
    /// PM2.5 in µg/m³.
    public var pm25: Double?
    /// Air temperature in °C.
    public var temperatureC: Double?
    public var capturedAt: Date
    /// Data source, e.g. "Open-Meteo".
    public var provider: String

    public init(aqi: Int, pm25: Double? = nil, temperatureC: Double? = nil, capturedAt: Date, provider: String = "Open-Meteo") {
        self.aqi = aqi
        self.pm25 = pm25
        self.temperatureC = temperatureC
        self.capturedAt = capturedAt
        self.provider = provider
    }

    public var aqiCategory: AQICategory { AQICategory(aqi: aqi) }
}

/// US EPA AQI buckets.
public enum AQICategory: String, Codable, Sendable, CaseIterable {
    case good = "Good"
    case moderate = "Moderate"
    case unhealthySensitive = "Unhealthy for Sensitive Groups"
    case unhealthy = "Unhealthy"
    case veryUnhealthy = "Very Unhealthy"
    case hazardous = "Hazardous"

    public init(aqi: Int) {
        switch aqi {
        case ..<51: self = .good
        case ..<101: self = .moderate
        case ..<151: self = .unhealthySensitive
        case ..<201: self = .unhealthy
        case ..<301: self = .veryUnhealthy
        default: self = .hazardous
        }
    }
}
