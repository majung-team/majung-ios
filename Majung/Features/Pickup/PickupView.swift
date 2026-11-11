import SwiftUI

struct PickupView: View {
    @Bindable var tracker: PickupTracker
    var resetLabel = "처음으로"
    var onReset: () -> Void

    @State private var editingPlace = false
    @State private var showArrivalMap = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let error = tracker.error { Text(error).foregroundStyle(.red) }
                if tracker.connectionProblem {
                    Label("연결이 끊겼어요. 다시 연결하고 있어요.", systemImage: "wifi.slash")
                        .foregroundStyle(.secondary)
                }

                if let snapshot = tracker.snapshot {
                    switch snapshot.status {
                    case .active:
                        if let place = snapshot.place { active(snapshot, place: place) }
                        else { ProgressView("만날 장소를 확인하고 있어요") }
                    case .arrived:
                        if let place = snapshot.place { arrival(snapshot, place: place) }
                        else { Text("마중 차량이 도착했어요").font(.title2.bold()) }
                        messages(snapshot)
                    case .completed, .cancelled, .expired, .inviteExpired:
                        finished(snapshot.status)
                    case .inviting, .waiting:
                        MajungCard {
                            Text("운전자 확인을 기다리고 있어요").font(.headline)
                            if let place = snapshot.place { Text(place.label).foregroundStyle(.secondary) }
                        }
                    }
                } else if tracker.connectionProblem {
                    Button("다시 확인") { Task { await tracker.refresh() } }
                } else {
                    ProgressView("픽업을 불러오고 있어요")
                }
            }
            .padding(16)
        }
        .refreshable { await tracker.refresh() }
        .navigationTitle("마중 픽업")
        .sheet(isPresented: $editingPlace) {
            if let place = tracker.snapshot?.place {
                PlaceProposalView(meetingPlace: place, tracker: tracker)
            }
        }
        .onChange(of: tracker.snapshot?.status) { _, status in
            if status != .active { editingPlace = false }
        }
    }

    private func active(_ snapshot: PickupSnapshot, place: PickupPlace) -> some View {
        Group {
            MajungCard {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let vehicle = tracker.currentVehicle()
                    VStack(alignment: .leading, spacing: 12) {
                        Text(MajungFormatting.etaText(vehicle)).font(.title2.bold()).accessibilityAddTraits(.isHeader)
                        if let name = snapshot.vehicleName, !name.isEmpty {
                            Label(name, systemImage: "car.fill").foregroundStyle(.secondary)
                        }
                        PickupMapView(place: place, vehicle: vehicle)
                    }
                }
            }
            MajungCard {
                Text("만날 장소").font(.subheadline).foregroundStyle(.secondary)
                Label(place.label, systemImage: "mappin.circle.fill").font(.headline)
                if let proposal = snapshot.placeProposal {
                    Divider()
                    Text(proposal.isPassenger ? "내가 제안한 장소" : "운전자가 제안한 장소")
                        .font(.subheadline).foregroundStyle(.secondary)
                    Text(proposal.place.label).font(.headline)
                    Text("새 장소가 확정될 때까지 위에 표시된 장소에서 만나요.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if proposal.isPassenger {
                        Button("제안 취소") { Task { await tracker.withdrawProposal() } }
                            .disabled(tracker.busy)
                    }
                } else {
                    Button("다른 장소 제안") { editingPlace = true }.disabled(tracker.busy)
                }
            }
            if let participant = snapshot.participant {
                MajungCard {
                    Text("탑승 준비 상태").font(.headline)
                    Text(participant.ready ? "준비 완료" : "준비 중")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await tracker.setReady(!participant.ready) }
                    } label: {
                        Text(participant.ready ? "준비 중으로 바꾸기" : "탑승 준비 완료")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(tracker.busy)
                    if participant.ready {
                        Text(
                            participant.readinessReceivedSequence >= participant.readinessSequence
                            ? "차량 앱에 전달됐어요."
                            : "준비 상태를 보냈어요."
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            messages(snapshot)
        }
    }

    private func arrival(_ snapshot: PickupSnapshot, place: PickupPlace) -> some View {
        MajungCard {
            Label("마중 차량이 도착했어요", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
                .accessibilityAddTraits(.isHeader)
            Text("만날 장소").font(.subheadline).foregroundStyle(.secondary)
            Text(place.label).font(.title3.bold())
            if let name = snapshot.vehicleName, !name.isEmpty {
                Label(name, systemImage: "car.fill").font(.title3.bold())
            }
            Button(showArrivalMap ? "지도 닫기" : "지도에서 차량 보기") { showArrivalMap.toggle() }
                .buttonStyle(.borderedProminent)
            if showArrivalMap {
                TimelineView(.periodic(from: .now, by: 1)) { _ in
                    let vehicle = tracker.currentVehicle()
                    PickupMapView(place: place, vehicle: vehicle)
                    if vehicle?.latitude == nil || vehicle?.longitude == nil {
                        Text("차량 위치를 확인할 수 없어요. 지도에 만날 장소를 표시했어요.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func messages(_ snapshot: PickupSnapshot) -> some View {
        MajungCard {
            Text("운전자에게 메시지").font(.headline)
            ScrollView(.horizontal) {
                HStack {
                    ForEach(["지금 내려가요", "입구 앞이에요", "곧 도착해요"], id: \.self) { text in
                        Button(text) { tracker.messageDraft = text }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .scrollIndicators(.hidden)
            TextField("메시지 입력", text: $tracker.messageDraft, axis: .vertical)
                .textFieldStyle(.roundedBorder)
            HStack {
                Text("\(tracker.messageDraft.utf16.count)/50자")
                    .font(.footnote)
                    .foregroundStyle(tracker.messageDraft.utf16.count > 50 ? Color.red : Color.secondary)
                Spacer()
                Button("전송") { Task { await tracker.sendMessage() } }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        tracker.busy ||
                        tracker.messageDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                        tracker.messageDraft.utf16.count > 50
                    )
            }
            if let recent = snapshot.quickMessage, !recent.text.isEmpty {
                Text("보낸 메시지 · \(recent.text)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else if tracker.messageSent {
                Text("메시지를 보냈어요.").font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func finished(_ status: PickupSnapshot.Status) -> some View {
        MajungCard {
            Text(
                status == .completed ? "잘 만났어요!" :
                status == .cancelled ? "픽업이 취소됐어요" : "픽업 시간이 지났어요"
            )
            .font(.title2.bold())
            .accessibilityAddTraits(.isHeader)
            Text("차량 위치 공유가 끝났어요.").foregroundStyle(.secondary)
            Button(resetLabel, action: onReset).buttonStyle(.borderedProminent)
        }
    }
}
