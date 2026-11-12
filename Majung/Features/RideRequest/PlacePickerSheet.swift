import SwiftUI

struct PlacePickerSheet: View {
    @Environment(\.dismiss) private var dismiss

    let target: RideTargetPerson
    @Bindable var rideModel: RideRequestViewModel
    var onSubmitted: () -> Void

    @State private var idempotencyRequestId = UUID()

    var body: some View {
        NavigationStack {
            PlaceComposerView(
                idPrefix: "ride",
                submitLabel: "이 장소로 마중 요청 보내기",
                busySubmitLabel: "요청 보내는 중…",
                busy: rideModel.busy,
                externalError: rideModel.error,
                onSelectionChanged: { idempotencyRequestId = UUID() },
                onSubmit: { place in
                    let ok = if let vehicle = target.vehicle {
                        await rideModel.submitRequest(vehicleId: vehicle.vehicleId, place: place, requestId: idempotencyRequestId)
                    } else {
                        await rideModel.submitRequest(driverId: target.driverId, place: place, requestId: idempotencyRequestId)
                    }
                    if ok {
                        onSubmitted()
                        dismiss()
                    }
                }
            ) {
                driverCard
            }
            .navigationTitle("만날 장소 선택")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("닫기") { dismiss() }
                        .disabled(rideModel.busy)
                }
            }
            .onAppear {
                rideModel.error = nil
            }
        }
    }

    private var driverCard: some View {
        MajungCard {
            if let vehicle = target.vehicle {
                HStack(spacing: 12) {
                    MajungMonogram(name: vehicle.summaryTitle, tint: .accentColor)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(vehicle.summaryTitle)
                            .font(.headline)
                        if let hint = vehicle.ownerHint, !hint.isEmpty {
                            Text("구별 힌트 · \(hint)")
                                .font(.subheadline)
                                .foregroundStyle(.primary)
                        }
                        Text(vehicle.vehicleCode)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                Text("이 차량(차종·번호·힌트)이 맞는지 확인한 뒤 만날 장소를 골라주세요. 수락되면 자주 타는 차량에 자동 저장돼요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
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
    }
}
