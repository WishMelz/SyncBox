import Foundation

/// Passwords are never persisted. The token is stored separately from preferences.
struct SavedConnection: Codable {
    var server: String
    var allowHTTP: Bool
    var deviceId: String?
    var deviceName: String
    var token: String? = nil
}
protocol SessionStore {
    func read() throws -> SavedConnection?
    func save(_ value: SavedConnection) throws
    func installationId() throws -> String
}
struct PreferencesConnectionStore: SessionStore {
    private let defaults: UserDefaults
    private let key = "syncbox.connection.preferences"

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func installationId() throws -> String {
        let key = "syncbox.installation.id.v1"
        if let saved = defaults.string(forKey: key), let uuid = UUID(uuidString: saved) {
            return uuid.uuidString.lowercased()
        }
        let id = UUID().uuidString.lowercased()
        defaults.set(id, forKey: key)
        return id
    }

    func read() throws -> SavedConnection? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try JSONDecoder().decode(SavedConnection.self, from: data)
    }
    func save(_ value: SavedConnection) throws {
        var preferences = value
        preferences.token = nil
        defaults.set(try JSONEncoder().encode(preferences), forKey: key)
    }
}

/// Private app-container storage avoids Keychain authorization prompts.
struct LocalSessionStore: SessionStore {
    private let preferences: PreferencesConnectionStore
    private let directory: URL
    private var tokenURL: URL { directory.appendingPathComponent("session.json") }
    private struct Credential: Codable { let server: String; let token: String }

    init(defaults: UserDefaults = .standard, directory: URL? = nil) {
        preferences = PreferencesConnectionStore(defaults: defaults)
        self.directory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SyncBox/Session", isDirectory: true)
    }

    func installationId() throws -> String { try preferences.installationId() }

    func read() throws -> SavedConnection? {
        guard var saved = try preferences.read() else { return nil }
        if FileManager.default.fileExists(atPath: tokenURL.path) {
            let credential = try JSONDecoder().decode(Credential.self, from: Data(contentsOf: tokenURL))
            if credential.server == saved.server { saved.token = credential.token }
        }
        return saved
    }

    func save(_ value: SavedConnection) throws {
        let manager = FileManager.default
        // Remove stale credentials before updating the destination server.
        if manager.fileExists(atPath: tokenURL.path) { try manager.removeItem(at: tokenURL) }
        try preferences.save(value)
        guard let token = value.token else { return }
        try manager.createDirectory(at: directory, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        var excludedDirectory = directory
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try excludedDirectory.setResourceValues(resources)
        let data = try JSONEncoder().encode(Credential(server: value.server, token: token))
        #if os(iOS)
        try data.write(to: tokenURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: tokenURL, options: .atomic)
        #endif
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
    }
}
