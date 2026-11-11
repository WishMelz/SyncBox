import Foundation

struct AppSettings: Decodable {
    struct Cleanup: Decodable { let enabled: Bool; let idleDays: Int; let lastRunAt: Double?; let lastDeletedCount: Int }
    struct Storage: Decodable { let fileCount: Int; let bytes: Int }
    let cleanup: Cleanup
    let storage: Storage
    let twoFactorEnabled: Bool
    let recoveryCodesRemaining: Int
}
struct CleanupInput: Encodable { let enabled: Bool; let idleDays: Int }
struct TwoFactorSetup: Decodable { let secret: String; let expiresIn: Int }
struct RecoveryCodes: Decodable { let recoveryCodes: [String] }
