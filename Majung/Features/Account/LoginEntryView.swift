import SwiftUI

struct LoginEntryView: View {
    @Bindable var account: AccountViewModel
    @Bindable var pickup: PickupViewModel
    @Binding var inviteLink: String
    var vehiclePendingMessage: String? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                if let vehiclePendingMessage {
                    MajungStatusBanner(message: vehiclePendingMessage, tint: .accentColor)
                }
                kakaoSection
                divider
                guestInviteCard
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("마중")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "location.circle.fill")
                .font(.largeTitle)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("기다림 없는 만남,\n마중으로 연결해요")
                .font(.title.bold())
                .accessibilityAddTraits(.isHeader)
            Text("차량의 도착 예정 시간과 만날 약속 장소를 한 화면에서 함께 확인해요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var kakaoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                Task { await account.signInWithKakao() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "message.fill")
                    Text(account.busy ? "로그인 중…" : "카카오로 시작하기")
                        .fontWeight(.bold)
                }
                .foregroundStyle(Color(red: 0.098, green: 0.098, blue: 0.098))
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(Color(red: 1.0, green: 0.898, blue: 0.0), in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(account.busy || account.restoring || !account.loginEnabled)
            .accessibilityIdentifier("kakao-login-button")

            if !account.loginEnabled {
                Text("현재 서버 로그인 설정을 준비하고 있어요. 아래 초대 링크로 바로 참여할 수 있어요.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            if let error = account.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var divider: some View {
        HStack(spacing: 10) {
            VStack { Divider() }
            Text("또는 비로그인 초대 참여")
                .font(.caption)
                .foregroundStyle(.secondary)
            VStack { Divider() }
        }
    }

    private var guestInviteCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("로그인 없이 바로 열기")
                .font(.caption.bold())
                .foregroundStyle(.green)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(.green.opacity(0.14), in: Capsule())

            Text("전달받은 마중 초대 링크가 있나요?")
                .font(.headline)
            Text("계정 로그인 없이 만날 장소를 확인하고 바로 픽업에 참여할 수 있어요.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            TextField("마중 초대 링크", text: $inviteLink, axis: .vertical)
                .textContentType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(12)
                .background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))

            HStack(spacing: 10) {
                PasteButton(payloadType: String.self) { values in
                    guard let value = values.first else { return }
                    inviteLink = value
                    Task { await pickup.openLink(value) }
                }
                .disabled(pickup.busy)

                Button {
                    Task { await pickup.openLink(inviteLink) }
                } label: {
                    Text("초대 확인하기")
                        .frame(maxWidth: .infinity, minHeight: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || pickup.busy)
            }

            if let error = pickup.error {
                Text(error)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
    }
}
