import AuthenticationServices
import Foundation
import UIKit

enum NativeAuthError: LocalizedError {
    case unavailable
    case failed
    case anchorMissing

    var errorDescription: String? {
        switch self {
        case .unavailable:
            return "현재 카카오 로그인을 준비하고 있어요."
        case .failed:
            return "카카오 로그인을 완료하지 못했어요. 다시 시도해주세요."
        case .anchorMissing:
            return "로그인 창을 열지 못했어요. 다시 시도해주세요."
        }
    }
}

@MainActor
final class NativeAuthSession: NSObject, ASWebAuthenticationPresentationContextProviding {
    private var activeSession: ASWebAuthenticationSession?

    func authenticate(url: URL, callbackScheme: String = "majung") async throws -> String {
        guard presentationAnchor(for: ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme, completionHandler: { _, _ in })) != nil else {
            throw NativeAuthError.anchorMissing
        }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: callbackScheme) { callbackURL, error in
                self.activeSession = nil
                if let asError = error as? ASWebAuthenticationSessionError,
                   asError.code == .canceledLogin {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                if error != nil {
                    continuation.resume(throwing: NativeAuthError.failed)
                    return
                }
                guard let callbackURL,
                      callbackURL.host?.lowercased() == "auth",
                      let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems else {
                    continuation.resume(throwing: NativeAuthError.failed)
                    return
                }
                if let status = items.first(where: { $0.name == "status" })?.value {
                    continuation.resume(throwing: status == "unavailable" ? NativeAuthError.unavailable : NativeAuthError.failed)
                    return
                }
                guard let code = items.first(where: { $0.name == "code" })?.value,
                      UUID(uuidString: code) != nil else {
                    continuation.resume(throwing: NativeAuthError.failed)
                    return
                }
                continuation.resume(returning: code)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.activeSession = session
            if !session.start() {
                self.activeSession = nil
                continuation.resume(throwing: NativeAuthError.failed)
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let foreground = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        if let keyWindow = foreground?.windows.first(where: { $0.isKeyWindow }) {
            return keyWindow
        }
        return foreground?.windows.first ?? ASPresentationAnchor()
    }
}
