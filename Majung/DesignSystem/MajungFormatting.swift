import CoreLocation
import Foundation

enum MajungFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func etaText(_ vehicle: PickupVehicle?) -> String {
        guard let seconds = vehicle?.durationSeconds else {
            return "도착 시간을 확인 중이에요"
        }
        return seconds < 60 ? "1분 이내 도착 예정" : "약 \((seconds + 59) / 60)분 후 도착 예정"
    }

    static func isApproachingSoon(_ vehicle: PickupVehicle?) -> Bool {
        guard let seconds = vehicle?.durationSeconds else { return false }
        return (0...180).contains(seconds)
    }

    static func minutesText(seconds: Int) -> String {
        seconds < 60 ? "1분 이내" : "약 \((seconds + 59) / 60)분"
    }

    static func distanceText(from vehicle: PickupVehicle?, to place: PickupPlace) -> String? {
        guard let vLat = vehicle?.latitude, let vLng = vehicle?.longitude else { return nil }
        let carLocation = CLLocation(latitude: vLat, longitude: vLng)
        let placeLocation = CLLocation(latitude: place.latitude, longitude: place.longitude)
        let meters = carLocation.distance(from: placeLocation)
        if meters < 1_000 {
            return "\(max(1, Int(meters.rounded())))m 남음"
        }
        return String(format: "%.1fkm 남음", meters / 1_000)
    }

    static func freshnessText(for vehicle: PickupVehicle?, updatedAt: Date?, now: Date = Date()) -> String? {
        guard let vehicle else { return nil }
        let baseAgeSeconds = max(0, (vehicle.ageMillis ?? 0) / 1_000)
        let localElapsed = updatedAt.map { max(0, Int(now.timeIntervalSince($0))) } ?? 0
        let totalAge = baseAgeSeconds + localElapsed
        return totalAge < 5 ? "실시간 갱신 중 · 방금 전" : "실시간 갱신 중 · \(totalAge)초 전"
    }

    static func lastCheckedText(updatedAt: Date?, refreshedAt: Date?, now _: Date = Date()) -> String? {
        guard let date = updatedAt ?? refreshedAt else { return nil }
        return "마지막 확인 · \(shortTime(date))"
    }

    static func relativeCheckText(since date: Date?, now: Date = Date()) -> String {
        guard let date else { return "방금 전" }
        let seconds = max(0, Int(now.timeIntervalSince(date)))
        if seconds < 15 { return "방금 전" }
        if seconds < 60 { return "\(seconds)초 전" }
        return "\(max(1, seconds / 60))분 전"
    }

    static func shortTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func shortDateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
    }

    static func appleMapsDirectionsURL(for place: PickupPlace) -> URL? {
        ExternalMapApp.apple.url(for: place, mode: .directions)
    }
}

enum ExternalMapApp: String, CaseIterable, Identifiable {
    case naver
    case kakao
    case apple

    enum Mode {
        case directions
        case viewPlace
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .naver: "네이버 지도"
        case .kakao: "카카오맵"
        case .apple: "Apple 지도"
        }
    }

    var schemeCheckURL: URL? {
        switch self {
        case .naver: URL(string: "nmap://")
        case .kakao: URL(string: "kakaomap://")
        case .apple: nil
        }
    }

    static func availableApps(canOpenURL: (URL) -> Bool) -> [ExternalMapApp] {
        allCases.filter { app in
            guard let checkURL = app.schemeCheckURL else { return true }
            return canOpenURL(checkURL)
        }
    }

    func url(for place: PickupPlace, mode: Mode) -> URL? {
        let trimmed = place.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayName = trimmed.isEmpty ? "만날 장소" : trimmed
        switch self {
        case .naver:
            var components = URLComponents(string: mode == .directions ? "nmap://route/walk" : "nmap://place")
            if mode == .directions {
                components?.queryItems = [
                    URLQueryItem(name: "dlat", value: "\(place.latitude)"),
                    URLQueryItem(name: "dlng", value: "\(place.longitude)"),
                    URLQueryItem(name: "dname", value: displayName),
                    URLQueryItem(name: "appname", value: "app.majung.ios")
                ]
            } else {
                components?.queryItems = [
                    URLQueryItem(name: "lat", value: "\(place.latitude)"),
                    URLQueryItem(name: "lng", value: "\(place.longitude)"),
                    URLQueryItem(name: "name", value: displayName),
                    URLQueryItem(name: "appname", value: "app.majung.ios")
                ]
            }
            return components?.url
        case .kakao:
            var components = URLComponents(string: mode == .directions ? "kakaomap://route" : "kakaomap://look")
            if mode == .directions {
                components?.queryItems = [
                    URLQueryItem(name: "ep", value: "\(place.latitude),\(place.longitude)"),
                    URLQueryItem(name: "by", value: "FOOT")
                ]
            } else {
                components?.queryItems = [
                    URLQueryItem(name: "p", value: "\(place.latitude),\(place.longitude)")
                ]
            }
            return components?.url
        case .apple:
            var components = URLComponents(string: "https://maps.apple.com/")
            if mode == .directions {
                components?.queryItems = [
                    URLQueryItem(name: "daddr", value: "\(place.latitude),\(place.longitude)"),
                    URLQueryItem(name: "dirflg", value: "w"),
                    URLQueryItem(name: "q", value: displayName)
                ]
            } else {
                components?.queryItems = [
                    URLQueryItem(name: "ll", value: "\(place.latitude),\(place.longitude)"),
                    URLQueryItem(name: "q", value: displayName)
                ]
            }
            return components?.url
        }
    }
}
