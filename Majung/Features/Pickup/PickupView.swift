import MapKit
import SwiftUI

struct PickupView: View {
    @Bindable var model: PickupViewModel
    @State private var editingPlace = false
    @State private var showArrivalMap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if model.connectionProblem {
                    Label("연결이 끊겼어요. 다시 연결하고 있어요.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }

                if let snapshot = model.snapshot {
                    switch snapshot.status {
                    case .active:
                        active(snapshot)
                    case .arrived:
                        arrival(snapshot)
                        messages
                    case .completed, .cancelled, .expired:
                        finished(snapshot.status)
                    case .inviting, .waiting:
                        card {
                            Text("운전자 확인을 기다리고 있어요").font(.headline)
                            Text(snapshot.place.label).foregroundStyle(.secondary)
                        }
                    }
                } else if model.connectionProblem {
                    Button("다시 확인") { Task { await model.refresh() } }
                } else {
                    ProgressView("픽업을 불러오고 있어요")
                }
            }
            .padding(16)
        }
        .refreshable { await model.refresh() }
        .navigationTitle("마중 픽업")
        .sheet(isPresented: $editingPlace) {
            if let place = model.snapshot?.place {
                PlaceProposalView(meetingPlace: place, model: model)
            }
        }
        .onChange(of: model.snapshot?.status) { _, status in
            if status != .active { editingPlace = false }
        }
    }

    private func active(_ snapshot: PickupSnapshot) -> some View {
        Group {
            card {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let vehicle = model.currentVehicle()
                    VStack(alignment: .leading, spacing: 12) {
                        Text(eta(vehicle)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        if let name = snapshot.vehicleName, !name.isEmpty {
                            Label(name, systemImage: "car.fill").foregroundStyle(.secondary)
                        }
                        PickupMap(place: snapshot.place, vehicle: vehicle)
                    }
                }
            }
            card {
                Text("만날 장소").font(.subheadline).foregroundStyle(.secondary)
                Label(snapshot.place.label, systemImage: "mappin.circle.fill").font(.headline)
                if let proposal = snapshot.placeProposal {
                    Divider()
                    Text(proposal.isPassenger ? "내가 제안한 장소" : "운전자가 제안한 장소")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(proposal.place.label).font(.headline)
                    Text("새 장소가 확정될 때까지 위에 표시된 장소에서 만나요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if proposal.isPassenger {
                        Button("제안 취소") { Task { await model.withdrawProposal() } }
                            .disabled(model.busy)
                    }
                } else {
                    Button("다른 장소 제안") { editingPlace = true }.disabled(model.busy)
                }
            }
            if let participant = snapshot.participant {
                card {
                    Text("탑승 준비 상태").font(.headline)
                    Text(participant.ready ? "준비 완료" : "준비 중")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.setReady(!participant.ready) }
                    } label: {
                        Text(participant.ready ? "준비 중으로 바꾸기" : "탑승 준비 완료")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                    if participant.ready {
                        Text(participant.readinessReceivedSequence >= participant.readinessSequence
                             ? "차량 앱에 전달됐어요." : "준비 상태를 보냈어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            messages
        }
    }

    private func arrival(_ snapshot: PickupSnapshot) -> some View {
        card {
            Label("마중 차량이 도착했어요", systemImage: "checkmark.circle.fill")
                .font(.title2.bold()).foregroundStyle(.green).accessibilityAddTraits(.isHeader)
            Text("만날 장소").font(.subheadline).foregroundStyle(.secondary)
            Text(snapshot.place.label).font(.title3.bold())
            if let name = snapshot.vehicleName, !name.isEmpty {
                Label(name, systemImage: "car.fill").font(.title3.bold())
            }
            Button(showArrivalMap ? "지도 닫기" : "지도에서 차량 보기") { showArrivalMap.toggle() }
                .buttonStyle(.borderedProminent)
            if showArrivalMap {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let vehicle = model.currentVehicle()
                    PickupMap(place: snapshot.place, vehicle: vehicle)
                    if vehicle?.latitude == nil || vehicle?.longitude == nil {
                        Text("차량 위치를 확인할 수 없어요. 지도에 만날 장소를 표시했어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var messages: some View {
        card {
            Text("운전자에게 메시지").font(.headline)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(["지금 내려가요", "입구 앞이에요", "곧 도착해요"], id: \.self) { text in
                        Button(text) { model.messageDraft = text }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .scrollIndicators(.hidden)
            TextField("메시지 입력", text: $model.messageDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("\(model.messageDraft.utf16.count)/50자")
                    .font(.footnote)
                    .foregroundStyle(model.messageDraft.utf16.count > 50 ? Color.red : Color.secondary)
                Spacer()
                Button("전송") { Task { await model.sendMessage() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy || model.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                              || model.messageDraft.utf16.count > 50)
            }
            if model.messageSent {
                Text("메시지를 보냈어요.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func finished(_ status: PickupSnapshot.Status) -> some View {
        card {
            Text(status == .completed ? "잘 만났어요!" :
                 status == .cancelled ? "픽업이 취소됐어요" : "픽업 시간이 지났어요")
                .font(.title2.bold()).accessibilityAddTraits(.isHeader)
            Text("차량 위치 공유가 끝났어요.").foregroundStyle(.secondary)
            Button("처음으로") { model.reset() }.buttonStyle(.borderedProminent)
        }
    }

    private func eta(_ vehicle: PickupVehicle?) -> String {
        guard let seconds = vehicle?.durationSeconds else { return "도착 시간을 확인 중이에요" }
        return seconds < 60 ? "1분 이내 도착 예정" : "약 \((seconds + 59) / 60)분 후 도착 예정"
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct PickupMap: View {
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
        .onChange(of: vehicleCoordinate != nil) { _, hasVehicle in if hasVehicle { recenter() } }
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
        camera = .rect(MKMapRect(x: (placePoint.x + carPoint.x) / 2 - width * 0.75,
                                 y: (placePoint.y + carPoint.y) / 2 - height * 0.75,
                                 width: width * 1.5, height: height * 1.5))
    }
}
