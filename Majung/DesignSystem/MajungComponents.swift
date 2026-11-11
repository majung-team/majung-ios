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

    static func shortTime(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    static func shortDateTime(_ date: Date) -> String {
        dateTimeFormatter.string(from: date)
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
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var resolvedRouteKey = ""

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(position: $camera) {
                if let vehicleCoordinate {
                    if !routeCoordinates.isEmpty && resolvedRouteKey == currentRouteKey {
                        MapPolyline(coordinates: routeCoordinates)
                            .stroke(Color.blue, lineWidth: 5)
                    } else {
                        MapPolyline(coordinates: [vehicleCoordinate, coordinate])
                            .stroke(
                                Color.blue.opacity(0.65),
                                style: StrokeStyle(lineWidth: 3.5, dash: [6, 5])
                            )
                    }
                }
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
                Label("재중심", systemImage: "scope")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
            }
            .accessibilityLabel("차량과 만날 장소 다시 보기")
            .buttonStyle(.bordered)
            .background(.regularMaterial, in: Capsule())
            .clipShape(Capsule())
            .padding(10)
        }
        .onAppear(perform: recenter)
        .onChange(of: place) { _, _ in recenter() }
        .onChange(of: vehicleCoordinate != nil) { _, hasVehicle in
            if hasVehicle { recenter() }
        }
        .task(id: currentRouteKey) {
            await updateRoute()
        }
    }

    private var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: place.latitude, longitude: place.longitude)
    }

    private var vehicleCoordinate: CLLocationCoordinate2D? {
        guard let latitude = vehicle?.latitude, let longitude = vehicle?.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    private var currentRouteKey: String {
        guard let vehicleCoordinate else { return "" }
        let vLat = Int((vehicleCoordinate.latitude * 2_000).rounded())
        let vLng = Int((vehicleCoordinate.longitude * 2_000).rounded())
        let pLat = Int((coordinate.latitude * 2_000).rounded())
        let pLng = Int((coordinate.longitude * 2_000).rounded())
        return "\(vLat),\(vLng)->\(pLat),\(pLng)"
    }

    private func updateRoute() async {
        let key = currentRouteKey
        guard !key.isEmpty, let start = vehicleCoordinate else {
            routeCoordinates = []
            resolvedRouteKey = ""
            return
        }
        if key == resolvedRouteKey && !routeCoordinates.isEmpty { return }

        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: start))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        request.transportType = .automobile

        do {
            let response = try await MKDirections(request: request).calculate()
            guard !Task.isCancelled, key == currentRouteKey, let polyline = response.routes.first?.polyline else { return }
            let count = polyline.pointCount
            var coords = [CLLocationCoordinate2D](repeating: kCLLocationCoordinate2DInvalid, count: count)
            polyline.getCoordinates(&coords, range: NSRange(location: 0, length: count))
            routeCoordinates = coords
            resolvedRouteKey = key
        } catch {
            // Dashed straight-line polyline remains visible when offline or routing is unavailable.
        }
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

struct ActivePickupSummaryCard: View {
    let item: RideRequestItem
    let tracking: PickupTracker
    let ctaLabel: String
    let ctaIdentifier: String
    let trailingMeta: String?
    let onOpen: () -> Void

    init(
        item: RideRequestItem,
        tracking: PickupTracker,
        ctaLabel: String,
        ctaIdentifier: String,
        trailingMeta: String? = nil,
        onOpen: @escaping () -> Void
    ) {
        self.item = item
        self.tracking = tracking
        self.ctaLabel = ctaLabel
        self.ctaIdentifier = ctaIdentifier
        self.trailingMeta = trailingMeta
        self.onOpen = onOpen
    }

    var body: some View {
        MajungCard {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                let vehicle = tracking.currentVehicle()
                let place = tracking.snapshot?.place ?? item.place
                let arrived = tracking.snapshot?.status == .arrived
                let freshness = arrived ? nil : MajungFormatting.freshnessText(
                    for: vehicle,
                    updatedAt: tracking.vehicleUpdatedAt,
                    now: context.date
                )
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        MajungStatusPill(text: arrived ? "차량 도착 완료" : "실시간 마중 진행 중", tint: .green)
                        if let distance = MajungFormatting.distanceText(from: vehicle, to: place), !arrived {
                            MajungStatusPill(text: distance, tint: .accentColor)
                        }
                        Spacer()
                        if let trailingMeta {
                            Text(trailingMeta)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text(arrived ? "마중 차량이 도착했어요" : MajungFormatting.etaText(vehicle))
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)

                    if let freshness {
                        Text(freshness)
                            .font(.caption)
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "mappin.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text(tracking.snapshot?.place?.label ?? item.place.label)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 8) {
                MajungMonogram(name: item.nickname, tint: .accentColor, size: 28)
                if let vehicleName = tracking.snapshot?.vehicleName, !vehicleName.isEmpty {
                    Text("\(item.nickname) 운전자 · \(vehicleName)")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("\(item.nickname) 운전자")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Button(action: onOpen) {
                HStack(spacing: 6) {
                    Text(ctaLabel)
                    Image(systemName: "chevron.right")
                        .font(.caption.bold())
                }
                .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier(ctaIdentifier)
        }
    }
}
