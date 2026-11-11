import CoreLocation
import MapKit
import SwiftUI

struct PlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: RideTargetPerson
    @Bindable var rideModel: RideRequestViewModel
    var onSubmitted: () -> Void

    @State private var locationService = LocationService()
    @State private var searchQuery = ""
    @State private var searchResults: [MKMapItem] = []
    @State private var searchedKeyword = ""
    @State private var searchPage = 0
    @State private var searching = false
    @State private var searchDone = false
    @State private var searchNote: String?

    @State private var selectedCoordinate: CLLocationCoordinate2D?
    @State private var selectionSource: SelectionSource?
    @State private var accuracyMeters: Double?
    @State private var locationCapturedAt: Date?
    @State private var labelDraft = ""
    @State private var localError: String?

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 37.5547, longitude: 126.9707),
            latitudinalMeters: 1_500,
            longitudinalMeters: 1_500
        )
    )
    @State private var mapCenter = CLLocationCoordinate2D(latitude: 37.5547, longitude: 126.9707)
    @State private var idempotencyRequestId = UUID()
    @FocusState private var searchFocused: Bool

    private let pageSize = 5

    private enum SelectionSource {
        case search(title: String, address: String?)
        case gps
        case mapPin
    }

    private var pagedResults: ArraySlice<MKMapItem> {
        let start = searchPage * pageSize
        guard start < searchResults.count else { return [] }
        let end = min(searchResults.count, start + pageSize)
        return searchResults[start..<end]
    }

    private var totalPages: Int {
        max(1, (searchResults.count + pageSize - 1) / pageSize)
    }

    private var trimmedLabel: String {
        labelDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        selectedCoordinate != nil && !trimmedLabel.isEmpty && trimmedLabel.count <= 120 && !rideModel.busy
    }

    var body: some View {
        NavigationStack {
            ScrollViewReader { scrollProxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        driverCard
                        searchCard {
                            withAnimation { scrollProxy.scrollTo("confirm-section", anchor: .bottom) }
                        }
                        mapCard {
                            withAnimation { scrollProxy.scrollTo("confirm-section", anchor: .bottom) }
                        }
                        confirmCard
                            .id("confirm-section")
                    }
                    .padding(16)
                }
                .background(Color(.systemGroupedBackground))
            }
            .navigationTitle("만날 장소 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(rideModel.busy)
                }
            }
        }
    }

    private var driverCard: some View {
        MajungCard {
            HStack(spacing: 12) {
                MajungMonogram(name: target.nickname, tint: .accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(target.nickname) 님께 마중 요청")
                        .font(.headline)
                    Text(target.majungId)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            Text("장소를 검색하거나 현재 위치·지도 핀으로 만날 곳을 정해주세요. 운전자가 수락하면 픽업 대기에 들어가요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func searchCard(onSelected: @escaping () -> Void) -> some View {
        MajungCard {
            Label("1. 장소 검색 · 현재 위치", systemImage: "magnifyingglass")
                .font(.headline)

            HStack(spacing: 8) {
                TextField("예: 강남역 2번 출구, 서울역", text: $searchQuery)
                    .focused($searchFocused)
                    .submitLabel(.search)
                    .onSubmit {
                        searchFocused = false
                        Task { await performSearch() }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("ride-place-search-field")

                Button(searching ? "검색 중…" : "장소 찾기") {
                    searchFocused = false
                    Task { await performSearch() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(searching || searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .accessibilityIdentifier("ride-place-search-button")
            }

            Button {
                searchFocused = false
                Task { await useCurrentLocation(onSelected: onSelected) }
            } label: {
                Label(locationService.locating ? "현재 위치 확인 중…" : "현재 위치 선택", systemImage: "location.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(locationService.locating || rideModel.busy)
            .accessibilityIdentifier("ride-location-button")

            if let searchNote {
                Text(searchNote)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            if searchDone {
                Divider()
                if searchResults.isEmpty {
                    Text("‘\(searchedKeyword)’ 검색 결과가 없어요. 지역을 함께 입력하거나 지도에서 선택해주세요.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    Text("‘\(searchedKeyword)’ 검색 결과 · 이름과 주소를 확인해주세요.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    ForEach(Array(pagedResults.enumerated()), id: \.offset) { _, item in
                        let place = PlaceSearchService.place(from: item, fallbackLabel: searchedKeyword)
                        Button {
                            chooseSearchResult(item: item, place: place)
                            onSelected()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(place.label)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.primary)
                                    Text(item.placemark.title ?? "주소 정보 없음 · 지도에서 위치를 확인해주세요")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isSameCoordinate(selectedCoordinate, item.placemark.coordinate),
                                   case .search = selectionSource {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .padding(10)
                            .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }

                    if totalPages > 1 {
                        HStack {
                            Button("이전 결과") { searchPage = max(0, searchPage - 1) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(searchPage == 0)
                            Spacer()
                            Text("\(searchPage + 1) / \(totalPages) 페이지")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("다음 결과") { searchPage = min(totalPages - 1, searchPage + 1) }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(searchPage >= totalPages - 1)
                        }
                    }
                }
            }
        }
    }

    private func mapCard(onSelected: @escaping () -> Void) -> some View {
        MajungCard {
            Label("2. 지도 핀으로 위치 지정", systemImage: "mappin.and.ellipse")
                .font(.headline)

            Map(position: $mapPosition) {
                if let selectedCoordinate {
                    Marker("선택한 장소", systemImage: "mappin", coordinate: selectedCoordinate)
                        .tint(.green)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                mapCenter = context.region.center
            }
            .overlay {
                Image(systemName: "scope")
                    .font(.title2.bold())
                    .foregroundStyle(.blue)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .frame(height: 185)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button("지도 중심을 만날 장소로 선택") {
                searchFocused = false
                chooseMapCenter()
                onSelected()
            }
            .buttonStyle(.bordered)
            .disabled(rideModel.busy)
            .accessibilityIdentifier("ride-place-map-select")
        }
    }

    private var confirmCard: some View {
        MajungCard {
            Text("3. 선택한 만날 장소 · 설명")
                .font(.headline)

            selectionSummary

            TextField("예: 1번 출구 택시 승강장 앞 (1~120자)", text: $labelDraft)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityIdentifier("ride-place-label-field")

            HStack {
                Text("\(trimmedLabel.count)/120자")
                    .font(.caption)
                    .foregroundStyle(trimmedLabel.count > 120 ? Color.red : Color.secondary)
                Spacer()
                Text("정차하기 안전한 위치로 적어주세요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage = localError ?? rideModel.error {
                MajungStatusBanner(message: errorMessage, tint: .red)
            }

            Button {
                Task { await submit() }
            } label: {
                Text(rideModel.busy ? "요청 보내는 중…" : "이 장소로 마중 요청 보내기")
                    .frame(maxWidth: .infinity, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canSubmit)
            .accessibilityIdentifier("ride-submit-button")
        }
    }

    @ViewBuilder
    private var selectionSummary: some View {
        if let selectedCoordinate, let selectionSource {
            switch selectionSource {
            case let .search(title, address):
                VStack(alignment: .leading, spacing: 2) {
                    Text("검색 선택 · \(title)")
                        .font(.footnote.weight(.semibold))
                    if let address {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            case .gps:
                let acc = Int(ceil(accuracyMeters ?? 0))
                Text("현재 위치 선택 (정확도 약 \(acc)m)")
                    .font(.footnote.weight(.semibold))
            case .mapPin:
                let lat = String(format: "%.4f", selectedCoordinate.latitude)
                let lng = String(format: "%.4f", selectedCoordinate.longitude)
                Text("지도 핀 위치 선택 (\(lat), \(lng))")
                    .font(.footnote.weight(.semibold))
            }
        } else {
            Text("아직 장소를 고르지 않았어요. 검색·현재 위치·지도 중 하나로 위치를 선택해주세요.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func performSearch() async {
        let keyword = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !searching else { return }
        searching = true
        searchNote = nil
        localError = nil
        defer { searching = false }
        do {
            let items = try await PlaceSearchService.search(query: keyword, near: mapCenter)
            searchResults = items
            searchedKeyword = keyword
            searchPage = 0
            searchDone = true
        } catch {
            searchNote = "장소 검색을 완료하지 못했어요. 지도에서 위치를 직접 선택해주세요."
        }
    }

    private func useCurrentLocation(onSelected: () -> Void) async {
        localError = nil
        rideModel.error = nil
        do {
            let location = try await locationService.requestCurrentLocation()
            selectedCoordinate = location.coordinate
            selectionSource = .gps
            accuracyMeters = location.horizontalAccuracy
            locationCapturedAt = Date()
            idempotencyRequestId = UUID()
            mapPosition = .region(MKCoordinateRegion(
                center: location.coordinate,
                latitudinalMeters: 600,
                longitudinalMeters: 600
            ))
            if trimmedLabel.isEmpty {
                labelDraft = "현재 위치 근처"
            }
            onSelected()
        } catch {
            localError = (error as? LocationFailure)?.errorDescription ?? "현재 위치를 확인하지 못했어요."
        }
    }

    private func chooseSearchResult(item: MKMapItem, place: PickupPlace) {
        selectedCoordinate = item.placemark.coordinate
        selectionSource = .search(title: place.label, address: item.placemark.title)
        accuracyMeters = nil
        locationCapturedAt = nil
        labelDraft = place.label
        localError = nil
        idempotencyRequestId = UUID()
        mapPosition = .region(MKCoordinateRegion(
            center: item.placemark.coordinate,
            latitudinalMeters: 700,
            longitudinalMeters: 700
        ))
    }

    private func chooseMapCenter() {
        selectedCoordinate = mapCenter
        selectionSource = .mapPin
        accuracyMeters = nil
        locationCapturedAt = nil
        localError = nil
        idempotencyRequestId = UUID()
    }

    private func submit() async {
        localError = nil
        guard let coordinate = selectedCoordinate else {
            localError = "먼저 만날 장소를 선택해주세요."
            return
        }
        if case .gps = selectionSource,
           let capturedAt = locationCapturedAt,
           Date().timeIntervalSince(capturedAt) > 120 {
            localError = "현재 위치가 오래됐어요. 현재 위치를 다시 선택해주세요."
            return
        }
        let place = PickupPlace(label: trimmedLabel, latitude: coordinate.latitude, longitude: coordinate.longitude)
        if await rideModel.submitRequest(driverId: target.driverId, place: place, requestId: idempotencyRequestId) {
            onSubmitted()
            dismiss()
        }
    }

    private func isSameCoordinate(_ a: CLLocationCoordinate2D?, _ b: CLLocationCoordinate2D) -> Bool {
        guard let a else { return false }
        return abs(a.latitude - b.latitude) < 0.00001 && abs(a.longitude - b.longitude) < 0.00001
    }
}
