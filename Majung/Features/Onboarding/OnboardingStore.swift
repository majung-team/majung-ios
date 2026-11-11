import Foundation

/// Persists whether the user has completed or dismissed first-launch onboarding.
enum OnboardingStore {
    static let defaultKey = "majung.onboarding.completed.v1"

    static func isCompleted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: defaultKey)
    }

    static func markCompleted(defaults: UserDefaults = .standard) {
        defaults.set(true, forKey: defaultKey)
    }

    static func reset(defaults: UserDefaults = .standard) {
        defaults.removeObject(forKey: defaultKey)
    }
}
