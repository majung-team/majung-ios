import CoreLocation
import Foundation
import Observation

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private(set) var locating = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard !locating else {
            throw LocationFailure.alreadyRequesting
        }
        locating = true
        defer { locating = false }

        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw LocationFailure.denied
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            break
        @unknown default:
            break
        }

        let location = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            self.continuation = cont
            self.manager.requestLocation()
        }

        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy <= 300 else {
            throw LocationFailure.inaccurate
        }
        return location
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let latest = locations.last else { return }
        Task { @MainActor in
            continuation?.resume(returning: latest)
            continuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            continuation?.resume(throwing: LocationFailure.unavailable)
            continuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard continuation != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                manager.requestLocation()
            case .denied, .restricted:
                continuation?.resume(throwing: LocationFailure.denied)
                continuation = nil
            case .notDetermined:
                break
            @unknown default:
                break
            }
        }
    }
}

enum LocationFailure: LocalizedError {
    case alreadyRequesting
    case denied
    case inaccurate
    case unavailable

    var errorDescription: String? {
        switch self {
        case .alreadyRequesting:
            "현재 위치를 확인하고 있어요."
        case .denied:
            "위치 권한을 허용한 뒤 현재 위치를 다시 선택해주세요."
        case .inaccurate:
            "위치 오차가 커요. GPS가 잘 잡히는 곳에서 다시 선택해주세요."
        case .unavailable:
            "현재 위치를 확인하지 못했어요. 지도에서 위치를 직접 고르거나 검색해주세요."
        }
    }
}
