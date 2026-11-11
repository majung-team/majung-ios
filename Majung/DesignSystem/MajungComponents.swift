import MapKit
import SwiftUI

enum MajungCodec {
    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]

        decoder.dateDecodingStrategy = .custom { container in
            let single = try container.singleValueContainer()
            let raw = try single.decode(String.self)
            if let date = fractional.date(from: raw) ?? plain.date(from: raw) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: single,
                debugDescription: "Invalid ISO-8601 timestamp: \(raw)"
            )
        }
        return decoder
    }()

    static let encoder = JSONEncoder()
}

enum MajungFormatting {
    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    static func etaText(_ vehicle: PickupVehicle?) -> String {
        guard let seconds = vehicle?.durationSeconds else {
            return "도착 시간을 확인 중이에요"
        }
        return seconds < 60 ? "1분 이내 도착 예정" : "약 \((seconds + 59) / 60)분 후 도착 예정"
    }

    static func minutesText(seconds: Int) -> String {
        seconds < 60 ? "1분 이내" : "약 \((seconds + 59) / 60)분"
    }

    static func shortTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }
}

struct MajungCard<Content: View>: View {
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

struct MajungStatusPill: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.14), in: Capsule())
    }
}

struct MajungStatusBanner: View {
    let message: String
    let tint: Color

    var body: some View {
        Text(message)
            .font(.footnote.weight(.medium))
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
    }
}

struct MajungMonogram: View {
    let name: String
    let tint: Color
    var size: CGFloat = 36

    private var initial: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "마" : String(trimmed.prefix(1))
    }

    var body: some View {
        Text(initial)
            .font(.subheadline.bold())
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: Circle())
    }
}

struct PickupMapView: View {
    let place: PickupPlace
    let vehicle: PickupVehicle?
    @State private var camera: MapCameraPosition = .automatic

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $camera) {
                Marker("만날 장소", systemImage: "mappin", coordinate: coordinate)
                    .tint(.green)
                if let vehicleCoordinate {
                    Marker("마중 차량", systemImage: "car.fill", coordinate: vehicleCoordinate)
                        .tint(.blue)
                }
            }
            .frame(height: 205)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            Button {
                recenter()
            } label: {
                Image(systemName: "scope").padding(6)
            }
            .accessibilityLabel("차량과 만날 장소 다시 보기")
            .buttonStyle(.borderedProminent)
            .padding(12)
        }
        .onAppear(perform: recenter)
        .onChange(of: place) { _, _ in recenter() }
        .onChange(of: vehicleCoordinate != nil) { _, hasVehicle in
            if hasVehicle { recenter() }
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    private var vehicleCoordinate: CLLocationCoordinate2D? {
        guard let latitude = vehicle?.latitude, let longitude = vehicle?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private func recenter() {
        let placePoint = MKMapPoint(coordinate)
        let carPoint = vehicleCoordinate.map(MKMapPoint.init) ?? placePoint
        let width = max(abs(placePoint.x - carPoint.x), 3_000)
        let height = max(abs(placePoint.y - carPoint.y), 3_000)
        camera = .rect(MKMapRect(
            x: (placePoint.x + carPoint.x) / 2 - width * 0.75,
            y: (placePoint.y + carPoint.y) / 2 - height * 0.75,
            width: width * 1.5,
            height: height * 1.5
        ))
    }
}

enum PlaceSearchService {
    static func search(query: String, near center: CLLocationCoordinate2D? = nil) async throws -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let center {
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 12_000,
                longitudinalMeters: 12_000
            )
        }
        let response = try await MKLocalSearch(request: request).start()
        return Array(response.mapItems.prefix(15))
    }

    static func place(from item: MKMapItem, fallbackLabel: String) -> PickupPlace {
        let rawLabel = item.name ?? item.placemark.title ?? fallbackLabel
        return PickupPlace(
            label: String(rawLabel.prefix(60)),
            latitude: item.placemark.coordinate.latitude,
            longitude: item.placemark.coordinate.longitude
        )
    }
}
