import CoreLocation

@MainActor
final class LocationService: NSObject, @preconcurrency CLLocationManagerDelegate {
    static let houston = CLLocationCoordinate2D(latitude: 29.7604, longitude: -95.3698)

    private let manager = CLLocationManager()
    private var coordinateContinuation: CheckedContinuation<CLLocationCoordinate2D, Never>?
    var authorizationDidChange: (() -> Void)?
    private(set) var isUsingDefaultLocation = true

    var authorizationStatus: CLAuthorizationStatus { manager.authorizationStatus }

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestWhenInUse() {
        manager.requestWhenInUseAuthorization()
    }

    func currentCoordinate() async -> CLLocationCoordinate2D {
        if let coordinate = manager.location?.coordinate {
            isUsingDefaultLocation = false
            return coordinate
        }
        guard authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways else {
            isUsingDefaultLocation = true
            return Self.houston
        }
        if coordinateContinuation != nil {
            return manager.location?.coordinate ?? Self.houston
        }

        return await withCheckedContinuation { continuation in
            coordinateContinuation = continuation
            manager.requestLocation()
            Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(5))
                self?.finish(with: nil)
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationDidChange?()
        switch manager.authorizationStatus {
        case .denied, .restricted:
            finish(with: nil)
        case .authorizedAlways, .authorizedWhenInUse:
            if coordinateContinuation != nil { manager.requestLocation() }
        case .notDetermined:
            break
        @unknown default:
            finish(with: nil)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        finish(with: locations.last?.coordinate)
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        finish(with: nil)
    }

    private func finish(with coordinate: CLLocationCoordinate2D?) {
        guard let continuation = coordinateContinuation else { return }
        coordinateContinuation = nil
        isUsingDefaultLocation = coordinate == nil
        continuation.resume(returning: coordinate ?? Self.houston)
    }
}
