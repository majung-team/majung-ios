import CryptoKit
import Foundation
import Security

struct AccountMember: Codable, Equatable {
    let memberId: UUID
    let majungId: String
    let nickname: String
    let profileReady: Bool
}

struct AccountSessionResponse: Decodable, Equatable {
    let loginEnabled: Bool
    let authenticated: Bool
    let member: AccountMember?
    let csrfToken: String?
}

struct AccountStoredSession: Codable, Equatable {
    let sessionCookie: String
}

enum AccountValidation {
    private static let nicknamePattern = #"^[\p{L}\p{N} _.-]{2,20}$"#

    static func normalizedNickname(_ input: String) -> String? {
        let stripped = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = stripped.precomposedStringWithCompatibilityMapping
        guard normalized.range(of: nicknamePattern, options: .regularExpression) != nil else {
            return nil
        }
        return normalized
    }

    static func pkceVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return base64Url(Data(bytes))
    }

    static func pkceChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64Url(Data(digest))
    }

    private static func base64Url(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
