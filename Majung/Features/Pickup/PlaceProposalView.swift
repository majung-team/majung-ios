import CoreLocation
import SwiftUI

struct PlaceProposalView: View {
    @Environment(\.dismiss) private var dismiss
    let meetingPlace: PickupPlace
    @Bindable var tracker: PickupTracker

    var body: some View {
        NavigationStack {
            PlaceComposerView(
                initialCenter: CLLocationCoordinate2D(latitude: meetingPlace.latitude, longitude: meetingPlace.longitude),
                idPrefix: "proposal",
                card1Title: "1. 새 장소 검색 · 현재 위치",
                card3Title: "3. 제안할 장소 · 설명",
                footerHint: "운전자가 새 장소를 확정하면 약속 장소가 바뀌어요.",
                submitLabel: "운전자에게 제안 보내기",
                busySubmitLabel: "보내는 중…",
                busy: tracker.busy,
                externalError: tracker.error,
                onSubmit: { place in
                    if await tracker.suggest(place) {
                        dismiss()
                    }
                }
            ) {
                MajungCard {
                    Text("현재 만날 장소")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Label(meetingPlace.label, systemImage: "mappin.circle.fill")
                        .font(.headline)
                }
            }
            .navigationTitle("다른 장소 제안")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(tracker.busy)
                }
            }
            .onAppear {
                tracker.error = nil
            }
        }
    }
}
