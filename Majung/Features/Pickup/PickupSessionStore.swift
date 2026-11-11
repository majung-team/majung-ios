import Foundation
import Security

enum PickupSessionStore {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "app.majung.ios.pickup",
        kSecAttrAccount as String: "participant"
    ]

    static func load() -> PickupSession? {
        let request = query.merging([kSecReturnData as String: true]) { _, new in new }
        var result: CFTypeRef?
        guard SecItemCopyMatching(request as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(PickupSession.self, from: data)
    }

    static func save(_ session: PickupSession) throws {
        let data = try JSONEncoder().encode(session)
        let values: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw StorageError() }
        let item = query.merging(values) { _, new in new }
            .merging([kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new }
        guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { throw StorageError() }
    }

    static func clear() {
        SecItemDelete(query as CFDictionary)
    }

    private struct StorageError: Error {}
}
