import Foundation

enum PickupSessionStore {
    private static let service = "app.majung.ios.pickup"
    private static let account = "participant"

    static func load() -> PickupSession? {
        MajungSessionKeychain.load(service: service, account: account, as: PickupSession.self)
    }

    static func save(_ session: PickupSession) throws {
        try MajungSessionKeychain.save(session, service: service, account: account)
    }

    static func clear() {
        MajungSessionKeychain.clear(service: service, account: account)
    }
}
