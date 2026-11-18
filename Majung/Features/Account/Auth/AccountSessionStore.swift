import Foundation
import Security

enum MajungSessionKeychain {
    static func load<Value: Decodable>(service: String, account: String, as type: Value.Type) -> Value? {
        let query = baseQuery(service: service, account: account)
            .merging([kSecReturnData as String: true]) { _, new in new }
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecSuccess, let data = result as? Data {
            return try? JSONDecoder().decode(Value.self, from: data)
        }
        #if targetEnvironment(simulator)
        if status == errSecMissingEntitlement || status == errSecItemNotFound,
           let data = UserDefaults.standard.data(forKey: defaultsKey(service: service, account: account)) {
            return try? JSONDecoder().decode(Value.self, from: data)
        }
        #endif
        return nil
    }

    static func save<Value: Encodable>(_ value: Value, service: String, account: String) throws {
        let data = try JSONEncoder().encode(value)
        let query = baseQuery(service: service, account: account)
        let values: [String: Any] = [kSecValueData as String: data]
        let updated = SecItemUpdate(query as CFDictionary, values as CFDictionary)
        if updated == errSecSuccess { return }

        let status: OSStatus
        if updated == errSecItemNotFound {
            let item = query.merging(values) { _, new in new }
                .merging([kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly]) { _, new in new }
            status = SecItemAdd(item as CFDictionary, nil)
        } else {
            status = updated
        }
        if status == errSecSuccess { return }

        #if targetEnvironment(simulator)
        // Unsigned simulator builds (e.g. CODE_SIGNING_ALLOWED=NO in CI) lack Keychain entitlements (-34018).
        if status == errSecMissingEntitlement {
            UserDefaults.standard.set(data, forKey: defaultsKey(service: service, account: account))
            return
        }
        #endif
        throw StorageError()
    }

    static func clear(service: String, account: String) {
        SecItemDelete(baseQuery(service: service, account: account) as CFDictionary)
        #if targetEnvironment(simulator)
        UserDefaults.standard.removeObject(forKey: defaultsKey(service: service, account: account))
        #endif
    }

    private static func baseQuery(service: String, account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private static func defaultsKey(service: String, account: String) -> String {
        "majung.simulator.session.\(service).\(account)"
    }

    private struct StorageError: Error {}
}

enum AccountSessionStore {
    private static let service = "app.majung.ios.account"
    private static let account = "session"

    static func load() -> AccountStoredSession? {
        MajungSessionKeychain.load(service: service, account: account, as: AccountStoredSession.self)
    }

    static func save(_ session: AccountStoredSession) throws {
        try MajungSessionKeychain.save(session, service: service, account: account)
    }

    static func clear() {
        MajungSessionKeychain.clear(service: service, account: account)
    }
}
