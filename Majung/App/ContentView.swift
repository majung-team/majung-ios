import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model = PickupViewModel()
    @State private var link = ""

    private var activeSession: PickupSession? { scenePhase == .active ? model.session : nil }

    var body: some View {
        NavigationStack {
            Group {
                switch model.page {
                case .entry: entry
                case .invitation: invitation
                case .pickup: PickupView(model: model)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(Color(red: 0.10, green: 0.39, blue: 0.85))
        .onOpenURL { url in
            Task { await model.openLink(url.absoluteString) }
        }
        .task(id: activeSession) {
            guard activeSession != nil else { return }
            await refreshUntilInactive()
        }
    }

    private func refreshUntilInactive() async {
        while !Task.isCancelled && model.session != nil {
            if scenePhase == .active { await model.refresh() }
            do { try await Task.sleep(for: .seconds(3)) } catch { return }
        }
    }

    private var entry: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Image(systemName: "location.circle.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                Text("마중").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                Text("초대 링크로 픽업에 참여해 만날 장소와 차량 도착 시간을 확인하세요.")
                    .foregroundStyle(.secondary)
                TextField("마중 초대 링크", text: $link, axis: .vertical)
                    .textContentType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .padding(12)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    Task { await model.openLink(link) }
                } label: {
                    Text("초대 확인하기").frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.busy)
                if let error = model.error { Text(error).foregroundStyle(.red) }
            }
            .padding(20)
        }
    }

    private var invitation: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let place = model.placeLabel, !model.linkUnavailable {
                    Text("마중에 초대받았어요").font(.title2.bold())
                    Label(place, systemImage: "mappin.circle.fill").font(.headline)
                    Text("참여하면 차량 위치와 도착 예정 시간을 확인하고, 준비 상태를 운전자에게 알릴 수 있어요.")
                        .foregroundStyle(.secondary)
                    Button {
                        Task { await model.join() }
                    } label: {
                        Text(model.busy ? "연결 중…" : "약속에 참여하기")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(model.busy)
                } else if model.busy {
                    ProgressView("초대를 확인하고 있어요")
                } else {
                    Text(model.linkUnavailable ? "초대를 사용할 수 없어요" : "초대를 확인하지 못했어요")
                        .font(.title2.bold())
                    if !model.linkUnavailable {
                        Button("다시 확인") { Task { await model.preview() } }
                            .buttonStyle(.borderedProminent)
                    }
                }
                if let error = model.error { Text(error).foregroundStyle(.red) }
                if !model.busy {
                    Button("다른 초대 열기") {
                        link = ""
                        model.reset()
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
            .padding(16)
        }
        .navigationTitle("마중 초대 확인")
    }
}
