import Foundation
import Security

struct DnevnikSession: Codable {
    var a: String
    var l: String

    init?(a: String?, l: String?) {
        guard let a, let l, Self.valid(a), Self.valid(l) else { return nil }
        self.a = a
        self.l = l
    }

    var cookieHeader: String {
        "DnevnikAuth_a=\(a)"
    }

    static func valid(_ value: String?) -> Bool {
        guard let value, !value.isEmpty, value.count <= 10_000 else { return false }
        return value.unicodeScalars.allSatisfy { scalar in
            (33...126).contains(Int(scalar.value)) && Int(scalar.value) != 59
        }
    }
}

protocol DnevnikSessionStore: AnyObject {
    func read() -> DnevnikSession?
    func save(_ session: DnevnikSession)
    func clear()
}

extension DnevnikSessionStore {
    var hasSession: Bool { read() != nil }
}

/// The two Dnevnik cookies live only in Keychain, never in defaults or logs.
final class KeychainDnevnikSessionStore: DnevnikSessionStore {
    private let service = "dev.shed.schedule.dnevnik"
    private let account = "session"

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func read() -> DnevnikSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let session = try? JSONDecoder().decode(DnevnikSession.self, from: data) else { return nil }
        return session
    }

    func save(_ session: DnevnikSession) {
        guard let data = try? JSONEncoder().encode(session) else { return }
        SecItemDelete(baseQuery as CFDictionary)
        var attributes = baseQuery
        attributes[kSecValueData as String] = data
        attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func clear() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
