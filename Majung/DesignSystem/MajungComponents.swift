import MapKit
import SwiftUI
import UIKit

@MainActor
func dismissMajungKeyboard() {
    var transaction = Transaction()
    transaction.disablesAnimations = true
    withTransaction(transaction) {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}

@MainActor
private enum MajungKeyboardTapRegistry {
    static let preservedViews = NSHashTable<UIView>.weakObjects()
}

private final class MajungPreserveHostView: UIView {
    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window != nil {
            MajungKeyboardTapRegistry.preservedViews.add(self)
        } else {
            MajungKeyboardTapRegistry.preservedViews.remove(self)
        }
    }
}

private struct MajungTapPreserveFrameBridge: UIViewRepresentable {
    func makeUIView(context: Context) -> MajungPreserveHostView {
        let view = MajungPreserveHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: MajungPreserveHostView, context: Context) {}

    static func dismantleUIView(_ uiView: MajungPreserveHostView, coordinator: ()) {
        MajungKeyboardTapRegistry.preservedViews.remove(uiView)
    }
}

private final class MajungDismisserHostView: UIView {
    var onHierarchyMove: (@MainActor (UIView) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        onHierarchyMove?(self)
    }
}

private struct MajungOutsideTapKeyboardDismisser: UIViewRepresentable {
    let isActive: Bool
    let onTapOutsideDismiss: @MainActor () -> Void
    let onSystemKeyboardHide: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTapOutsideDismiss: onTapOutsideDismiss,
            onSystemKeyboardHide: onSystemKeyboardHide
        )
    }

    func makeUIView(context: Context) -> MajungDismisserHostView {
        let view = MajungDismisserHostView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        view.onHierarchyMove = { hostView in
            context.coordinator.attachIfNeeded(from: hostView)
        }
        return view
    }

    func updateUIView(_ uiView: MajungDismisserHostView, context: Context) {
        context.coordinator.onTapOutsideDismiss = onTapOutsideDismiss
        context.coordinator.onSystemKeyboardHide = onSystemKeyboardHide
        context.coordinator.isActive = isActive
        context.coordinator.attachIfNeeded(from: uiView)
    }

    static func dismantleUIView(_ uiView: MajungDismisserHostView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isActive = false {
            didSet {
                tapRecognizer.isEnabled = isActive
                panRecognizer.isEnabled = isActive
                if !isActive {
                    panDismissedCurrentGesture = false
                }
            }
        }
        var onTapOutsideDismiss: @MainActor () -> Void
        var onSystemKeyboardHide: @MainActor () -> Void
        private weak var attachedWindow: UIWindow?
        private var hideObserver: NSObjectProtocol?
        private var panDismissedCurrentGesture = false
        private lazy var tapRecognizer: UITapGestureRecognizer = configureDismissGesture(
            UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        )
        private lazy var panRecognizer: UIPanGestureRecognizer = configureDismissGesture(
            UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        )

        private func configureDismissGesture<Gesture: UIGestureRecognizer>(_ recognizer: Gesture) -> Gesture {
            recognizer.cancelsTouchesInView = false
            recognizer.delaysTouchesBegan = false
            recognizer.delaysTouchesEnded = false
            recognizer.delegate = self
            recognizer.isEnabled = false
            return recognizer
        }

        init(
            onTapOutsideDismiss: @escaping @MainActor () -> Void,
            onSystemKeyboardHide: @escaping @MainActor () -> Void
        ) {
            self.onTapOutsideDismiss = onTapOutsideDismiss
            self.onSystemKeyboardHide = onSystemKeyboardHide
            super.init()
        }

        func attachIfNeeded(from hostView: UIView) {
            guard let window = hostView.window else { return }
            if attachedWindow !== window {
                attachedWindow?.removeGestureRecognizer(tapRecognizer)
                attachedWindow?.removeGestureRecognizer(panRecognizer)
                window.addGestureRecognizer(tapRecognizer)
                window.addGestureRecognizer(panRecognizer)
                attachedWindow = window
            }
            if hideObserver == nil {
                hideObserver = NotificationCenter.default.addObserver(
                    forName: UIResponder.keyboardWillHideNotification,
                    object: nil,
                    queue: .main
                ) { [weak self] _ in
                    Task { @MainActor [weak self] in
                        guard let self, self.isActive else { return }
                        self.onSystemKeyboardHide()
                    }
                }
            }
            if isActive {
                enableImmediateScrollDismiss(from: hostView)
                Task { @MainActor [weak self, weak hostView] in
                    guard let self, let hostView, self.isActive else { return }
                    self.enableImmediateScrollDismiss(from: hostView)
                }
            }
            tapRecognizer.isEnabled = isActive
            panRecognizer.isEnabled = isActive
        }

        func detach() {
            tapRecognizer.isEnabled = false
            panRecognizer.isEnabled = false
            attachedWindow?.removeGestureRecognizer(tapRecognizer)
            attachedWindow?.removeGestureRecognizer(panRecognizer)
            attachedWindow = nil
            if let hideObserver {
                NotificationCenter.default.removeObserver(hideObserver)
                self.hideObserver = nil
            }
        }

        private func enableImmediateScrollDismiss(from hostView: UIView) {
            var root: UIView? = hostView
            var responder: UIResponder? = hostView
            while let next = responder?.next {
                if let vc = next as? UIViewController {
                    root = vc.view
                }
                responder = next
            }
            guard let rootView = root ?? hostView.window else { return }
            applyDragDismissIfNeeded(in: rootView)
        }

        private func applyDragDismissIfNeeded(in view: UIView) {
            if view is MKMapView {
                return
            }
            if let scrollView = view as? UIScrollView,
               scrollView.keyboardDismissMode != .onDrag,
               (scrollView is UICollectionView || scrollView is UITableView || scrollView.alwaysBounceVertical || scrollView.contentSize.height > scrollView.bounds.height) {
                scrollView.keyboardDismissMode = .onDrag
            }
            for child in view.subviews {
                applyDragDismissIfNeeded(in: child)
            }
        }

        @objc private func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard recognizer.state == .ended, isActive else { return }
            onTapOutsideDismiss()
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began:
                panDismissedCurrentGesture = false
            case .changed:
                guard isActive, !panDismissedCurrentGesture else { return }
                let translation = recognizer.translation(in: attachedWindow)
                if abs(translation.y) >= 12 && abs(translation.y) > abs(translation.x) * 1.25 {
                    panDismissedCurrentGesture = true
                    onTapOutsideDismiss()
                }
            case .ended, .cancelled, .failed:
                panDismissedCurrentGesture = false
            default:
                break
            }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            MainActor.assumeIsolated {
                guard isActive, let attachedWindow, touch.window === attachedWindow else {
                    return false
                }
                for view in MajungKeyboardTapRegistry.preservedViews.allObjects {
                    guard view.window === attachedWindow, !view.isHidden, view.alpha > 0 else {
                        continue
                    }
                    if view.bounds.contains(touch.location(in: view)) {
                        return false
                    }
                }
                let ignoreMaps = (gestureRecognizer === panRecognizer)
                var current = touch.view
                while let view = current {
                    if view is UITextInput || view is UIControl {
                        return false
                    }
                    if ignoreMaps, view is MKMapView {
                        return false
                    }
                    current = view.superview
                }
                return true
            }
        }

        nonisolated func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}

struct MajungClearInputButton: View {
    @Binding var text: String
    var accessibilityLabel: String = "입력 내용 지우기"

    var body: some View {
        if !text.isEmpty {
            Button {
                text = ""
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
        }
    }
}

extension View {
    func majungKeyboardDismiss(isFocused: FocusState<Bool>.Binding) -> some View {
        majungKeyboardDismissContainer(isActive: isFocused.wrappedValue) {
            isFocused.wrappedValue = false
        }
    }

    func majungKeyboardDismiss<Field: Hashable>(focusedField: FocusState<Field?>.Binding) -> some View {
        majungKeyboardDismissContainer(isActive: focusedField.wrappedValue != nil) {
            focusedField.wrappedValue = nil
        }
    }

    func majungPreserveKeyboardOnTap() -> some View {
        background(MajungTapPreserveFrameBridge())
    }

    func majungInputSurface(cornerRadius: CGFloat = 12) -> some View {
        padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                Color(uiColor: .tertiarySystemGroupedBackground),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .majungPreserveKeyboardOnTap()
    }

    @ViewBuilder
    func majungGlassCapsule() -> some View {
        if #available(iOS 26.0, *) {
            self.glassEffect(.regular.interactive(), in: .capsule)
        } else {
            self
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(.primary.opacity(0.12), lineWidth: 0.75)
                )
                .shadow(color: .black.opacity(0.08), radius: 8, y: 3)
        }
    }

    private func majungKeyboardDismissContainer(
        isActive: Bool,
        dismiss: @escaping @MainActor () -> Void
    ) -> some View {
        let clearFocusOnly: @MainActor () -> Void = {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                dismiss()
            }
        }
        let performDismiss: @MainActor () -> Void = {
            clearFocusOnly()
            dismissMajungKeyboard()
        }
        return scrollDismissesKeyboard(.immediately)
            .background(
                MajungOutsideTapKeyboardDismisser(
                    isActive: isActive,
                    onTapOutsideDismiss: performDismiss,
                    onSystemKeyboardHide: clearFocusOnly
                )
            )
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if isActive {
                    HStack {
                        Spacer()
                        Button {
                            performDismiss()
                        } label: {
                            Label("키보드 닫기", systemImage: "keyboard.chevron.compact.down")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.primary)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .majungGlassCapsule()
                        .accessibilityLabel("키보드 닫기")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                    .padding(.top, 4)
                }
            }
    }
}

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

struct PlaceSearchCandidate: Identifiable, Hashable {
    enum Source: String, Hashable {
        case kakao
        case mapKit
    }

    let id: String
    let label: String
    let address: String?
    let category: String?
    let latitude: Double
    let longitude: Double
    let source: Source

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var pickupPlace: PickupPlace {
        PickupPlace(label: String(label.prefix(60)), latitude: latitude, longitude: longitude)
    }

    var detailText: String {
        let trimmedAddress = address?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmedAddress, !trimmedAddress.isEmpty {
            return trimmedAddress
        }
        return "주소 정보 없음 · 지도에서 위치를 확인해주세요"
    }
}

struct PlaceSearchAPIResponse: Decodable, Equatable {
    struct Item: Decodable, Equatable {
        let label: String
        let address: String?
        let category: String?
        let latitude: Double
        let longitude: Double
    }

    let enabled: Bool
    let items: [Item]
    let hasNext: Bool
}

struct PlaceSearchResultPage: Equatable {
    let candidates: [PlaceSearchCandidate]
    let hasNext: Bool
    let usedFallback: Bool
}

enum PlaceSearchService {
    private static let defaultSession = URLSession(configuration: .ephemeral)

    static func searchURL(
        query: String,
        page: Int = 1,
        near center: CLLocationCoordinate2D? = nil,
        baseURL: URL = APIBaseURL.root
    ) -> URL? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let clampedPage = min(max(page, 1), 3)
        let endpoint = baseURL.appendingPathComponent("places").appendingPathComponent("search")
        guard var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false) else { return nil }
        var queryItems = [
            URLQueryItem(name: "query", value: String(trimmed.prefix(80))),
            URLQueryItem(name: "page", value: String(clampedPage))
        ]
        if let center {
            queryItems.append(URLQueryItem(name: "latitude", value: String(center.latitude)))
            queryItems.append(URLQueryItem(name: "longitude", value: String(center.longitude)))
        }
        components.queryItems = queryItems
        return components.url
    }

    static func search(
        query: String,
        page: Int = 1,
        near center: CLLocationCoordinate2D? = nil,
        baseURL: URL = APIBaseURL.root,
        session: URLSession = defaultSession,
        mapKitFallback: ((String, CLLocationCoordinate2D?) async throws -> [PlaceSearchCandidate])? = nil
    ) async throws -> PlaceSearchResultPage {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let clampedPage = min(max(page, 1), 3)
        guard !trimmed.isEmpty else {
            return PlaceSearchResultPage(candidates: [], hasNext: false, usedFallback: false)
        }

        if let url = searchURL(query: trimmed, page: clampedPage, near: center, baseURL: baseURL) {
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            request.httpMethod = "GET"
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (data, response) = try await session.data(for: request)
                if let http = response as? HTTPURLResponse,
                   (200..<300).contains(http.statusCode),
                   let decoded = try? MajungCodec.decoder.decode(PlaceSearchAPIResponse.self, from: data),
                   decoded.enabled {
                    let mapped = decoded.items.enumerated().map { index, item in
                        let cleanedLabel = item.label.trimmingCharacters(in: .whitespacesAndNewlines)
                        let displayLabel = cleanedLabel.isEmpty ? trimmed : cleanedLabel
                        return PlaceSearchCandidate(
                            id: "kakao-\(clampedPage)-\(index)-\(displayLabel)-\(item.latitude)-\(item.longitude)",
                            label: String(displayLabel.prefix(60)),
                            address: item.address,
                            category: item.category,
                            latitude: item.latitude,
                            longitude: item.longitude,
                            source: .kakao
                        )
                    }
                    if !mapped.isEmpty {
                        return PlaceSearchResultPage(
                            candidates: mapped,
                            hasNext: decoded.hasNext && clampedPage < 3,
                            usedFallback: false
                        )
                    }
                    if clampedPage > 1 {
                        return PlaceSearchResultPage(candidates: [], hasNext: false, usedFallback: false)
                    }
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Fall back to MapKit on transient server or network failure when searching page 1.
            }
        }

        guard clampedPage == 1 else {
            return PlaceSearchResultPage(candidates: [], hasNext: false, usedFallback: true)
        }

        let fallback = mapKitFallback ?? searchMapKit
        let mapKitItems = try await fallback(trimmed, center)
        return PlaceSearchResultPage(candidates: mapKitItems, hasNext: false, usedFallback: true)
    }

    static func searchMapKit(query: String, near center: CLLocationCoordinate2D? = nil) async throws -> [PlaceSearchCandidate] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        if let center {
            request.region = MKCoordinateRegion(
                center: center,
                latitudinalMeters: 12_000,
                longitudinalMeters: 12_000
            )
        }
        do {
            let response = try await MKLocalSearch(request: request).start()
            return response.mapItems.prefix(15).enumerated().map { index, item in
                let coord = item.placemark.coordinate
                let rawLabel = item.name ?? item.placemark.title ?? query
                return PlaceSearchCandidate(
                    id: "mapkit-\(index)-\(rawLabel)-\(coord.latitude)-\(coord.longitude)",
                    label: String(rawLabel.prefix(60)),
                    address: item.placemark.title,
                    category: nil,
                    latitude: coord.latitude,
                    longitude: coord.longitude,
                    source: .mapKit
                )
            }
        } catch let error as MKError where error.code == .placemarkNotFound {
            return []
        }
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
