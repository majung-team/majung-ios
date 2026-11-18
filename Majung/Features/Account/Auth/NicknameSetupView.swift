import SwiftUI

struct NicknameSetupView: View {
    @Bindable var account: AccountViewModel
    @State private var draft = ""
    @FocusState private var nicknameFocused: Bool

    private var normalizedCount: Int {
        draft.trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCompatibilityMapping
            .count
    }

    private var isValid: Bool {
        AccountValidation.normalizedNickname(draft) != nil
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("최초 로그인 · 닉네임 설정")
                        .font(.caption.bold())
                        .foregroundStyle(.tint)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(.tint.opacity(0.12), in: Capsule())

                    Text("어떤 이름으로 만날까요?")
                        .font(.title.bold())
                        .accessibilityAddTraits(.isHeader)

                    Text("운전자와 지인에게 표시될 이름이에요. 설정에서 언제든 바꿀 수 있어요.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        TextField("닉네임 (2~20자)", text: $draft)
                            .focused($nicknameFocused)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit {
                                nicknameFocused = false
                                if isValid && !account.busy {
                                    Task { _ = await account.saveNickname(draft) }
                                }
                            }
                            .onChange(of: draft) { _, _ in
                                if account.error != nil { account.error = nil }
                            }
                            .accessibilityIdentifier("nickname-setup-field")

                        MajungClearInputButton(text: $draft, accessibilityLabel: "닉네임 지우기")
                    }
                    .majungInputSurface()

                    HStack {
                        Text("문자·숫자·공백·밑줄·점·하이픈 2~20자")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(normalizedCount)/20자")
                            .font(.footnote)
                            .foregroundStyle(normalizedCount > 20 ? Color.red : Color.secondary)
                    }

                    if let error = account.error {
                        Text(error)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                .padding(16)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))

                Button {
                    nicknameFocused = false
                    Task { _ = await account.saveNickname(draft) }
                } label: {
                    Text(account.busy ? "저장 중…" : "이 이름으로 시작")
                        .frame(maxWidth: .infinity, minHeight: 40)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid || account.busy)
                .accessibilityIdentifier("nickname-setup-submit")

                Button("다른 계정으로 로그인", role: .destructive) {
                    nicknameFocused = false
                    Task { await account.logout() }
                }
                .disabled(account.busy)
            }
            .padding(20)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("이름 설정")
        .navigationBarTitleDisplayMode(.inline)
        .majungKeyboardDismiss(isFocused: $nicknameFocused)
    }
}
