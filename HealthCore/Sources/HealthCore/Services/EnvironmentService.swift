import Foundation

/// Provides the environmental snapshot attached to each recorded event.
public protocol EnvironmentService: Sendable {
    func currentSnapshot() async throws -> EnvironmentSnapshot
}

/// Keyless Open-Meteo air-quality client. Defaults to Houston, TX.
public struct OpenMeteoEnvironmentService: EnvironmentService {
    public var latitude: Double
    public var longitude: Double
    private let session: URLSession

    public init(latitude: Double = 29.7604, longitude: Double = -95.3698, session: URLSession = .shared) {
        self.latitude = latitude
        self.longitude = longitude
        self.session = session
    }

    struct Response: Decodable {
        struct Current: Decodable {
            let us_aqi: Int
            let pm2_5: Double?
        }
        let current: Current
    }

    public func currentSnapshot() async throws -> EnvironmentSnapshot {
        var components = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "us_aqi,pm2_5")
        ]
        let (data, _) = try await session.data(from: components.url!)
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return EnvironmentSnapshot(
            aqi: decoded.current.us_aqi,
            pm25: decoded.current.pm2_5,
            capturedAt: Date(),
            provider: "Open-Meteo"
        )
    }
}

/// Deterministic fallback used in demo mode and whenever the network is unavailable.
public struct CannedEnvironmentService: EnvironmentService {
    public var snapshot: EnvironmentSnapshot

    public init(aqi: Int = 112, pm25: Double = 38.5) {
        self.snapshot = EnvironmentSnapshot(aqi: aqi, pm25: pm25, capturedAt: Date(), provider: "Demo")
    }

    public func currentSnapshot() async throws -> EnvironmentSnapshot {
        var s = snapshot
        s.capturedAt = Date()
        return s
    }
}
