// AppConfig.swift — where the app finds the backend, and whether to use bundled stub JSON.
// Change both at runtime from the gear icon (Developer settings); no rebuild needed.

import Foundation

enum AppConfig {
    private static let baseURLKey = "orbit.apiBaseURL"
    private static let useStubsKey = "orbit.useStubs"

    /// Runtime override → Info.plist `ORBIT_API_BASE_URL` → localhost.
    static var apiBaseURL: URL {
        if let saved = UserDefaults.standard.string(forKey: baseURLKey), let url = URL(string: saved) {
            return url
        }
        if let fromPlist = Bundle.main.object(forInfoDictionaryKey: "ORBIT_API_BASE_URL") as? String,
           let url = URL(string: fromPlist) {
            return url
        }
        return URL(string: "http://localhost:3000")!
    }

    static func setAPIBaseURL(_ value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, URL(string: trimmed) != nil else { return }
        UserDefaults.standard.set(trimmed, forKey: baseURLKey)
    }

    /// Defaults to `true` so every screen works before the backend is deployed.
    static var useStubs: Bool {
        get { UserDefaults.standard.object(forKey: useStubsKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: useStubsKey) }
    }
}
