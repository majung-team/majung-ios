import MapKit
import SwiftUI

struct PlaceProposalView: View {
    @Environment(\.dismiss) private var dismiss
    let meetingPlace: PickupPlace
    @Bindable var tracker: PickupTracker

    @State private var query = ""
    @State private var results: [MKMapItem] = []
    @State private var selected: PickupPlace?
    @State private var searching = false
    @State private var searchNote: String?
    @State private var showMap = false
    @State private var mapCenter: CLLocationCoordinate2D?
    @State private var pinLabel = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("현재 만날 장소") { Text(meetingPlace.label) }
                Section("새 장소 검색") {
                    TextField("장소 이름이나 주소", text: $query)
                        .submitLabel(.search)
                        .onSubmit { Task { await search() } }
                    Button(searching ? "검색 중…" : "검색") { Task { await search() } }
                        .disabled(searching || query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    if let searchNote { Text(searchNote).foregroundStyle(.secondary) }
                    ForEach(Array(results.enumerated()), id: \.offset) { _, result in
                        let place = PlaceSearchService.place(from: result, fallbackLabel: query)
                        Button {
                            selected = place
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.label).foregroundStyle(.primary)
                                    if let address = result.placemark.title {
                                        Text(address).font(.footnote).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if selected == place { Image(systemName: "checkmark") }
                            }
                        }
                        .accessibilityAddTraits(selected == place ? [.isSelected] : [])
                    }
                }
                Section("지도에서 지정") {
                    Button(showMap ? "지도 닫기" : "지도에서 장소 고르기") { showMap.toggle() }
                    if showMap {
                        mapPicker
                        TextField("장소 이름", text: $pinLabel)
                        Button("지도 중심 선택") {
                            guard let mapCenter else { return }
                            selected = PickupPlace(
                                label: pinLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                                latitude: mapCenter.latitude,
                                longitude: mapCenter.longitude
                            )
                        }
                        .disabled(
                            mapCenter == nil ||
                            pinLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                            pinLabel.utf16.count > 120
                        )
                    }
                }
                if let selected {
                    Section("제안할 장소") {
                        Text(selected.label)
                        Text("운전자가 새 장소를 확정하면 약속 장소가 바뀌어요.")
                            .foregroundStyle(.secondary)
                        Button(tracker.busy ? "보내는 중…" : "운전자에게 제안 보내기") {
                            Task { if await tracker.suggest(selected) { dismiss() } }
                        }
                        .disabled(tracker.busy)
                        if let error = tracker.error { Text(error).foregroundStyle(.red) }
                    }
                }
            }
            .navigationTitle("다른 장소 제안")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                }
            }
        }
    }

    private var mapPicker: some View {
        let center = CLLocationCoordinate2D(latitude: meetingPlace.latitude, longitude: meetingPlace.longitude)
        return Map(initialPosition: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: 700,
            longitudinalMeters: 700
        )))
        .onMapCameraChange(frequency: .onEnd) { mapCenter = $0.region.center }
        .onAppear { mapCenter = center }
        .overlay {
            Image(systemName: "scope")
                .font(.title2.bold())
                .foregroundStyle(.blue)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .frame(height: 180)
        .accessibilityLabel("지도 중심을 옮겨 새 만남 장소를 지정하세요")
    }

    private func search() async {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !searching else { return }
        searching = true
        selected = nil
        results = []
        searchNote = nil
        defer { searching = false }
        let center = CLLocationCoordinate2D(latitude: meetingPlace.latitude, longitude: meetingPlace.longitude)
        do {
            results = Array(try await PlaceSearchService.search(query: text, near: center).prefix(10))
            if results.isEmpty { searchNote = "검색 결과가 없어요." }
        } catch {
            searchNote = "장소를 찾지 못했어요. 다른 이름이나 주소로 검색해주세요."
        }
    }
}
