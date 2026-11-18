import MapKit
import SwiftUI

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
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .contentShape(Capsule())
            }
            .accessibilityLabel("차량과 만날 장소 다시 보기")
            .buttonStyle(.plain)
            .majungGlassCapsule()
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
                        MajungStatusPill(text: arrived ? "차량 도착 완료" : "픽업 진행 중", tint: arrived ? .green : .accentColor)
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

                    if !arrived {
                        Text(freshness ?? "차량 위치 확인 중")
                            .font(.caption)
                            .foregroundStyle(vehicle == nil ? Color.secondary : Color.green)
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
