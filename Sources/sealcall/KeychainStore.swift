import Foundation
import Security
import SealcallCore

struct KeychainStore: RouteStore, @unchecked Sendable {
    static let service = "sealcall"

    private let keychain: SecKeychain

    init(path: String) throws {
        var keychain: SecKeychain?
        let status = SecKeychainOpen(path, &keychain)
        guard status == errSecSuccess, let keychain else {
            throw SealError("cannot open keychain \(path): \(message(status))")
        }
        self.keychain = keychain
    }

    func read(_ route: String) throws -> Route {
        var query = baseQuery(route)
        query[kSecMatchSearchList as String] = [keychain]
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        try check(status, route: route)
        guard let data = result as? Data else {
            throw SealError("route \(route): the Keychain returned no data")
        }
        do {
            return try JSONDecoder().decode(Route.self, from: data)
        } catch {
            throw SealError("route \(route): the Keychain item is not a sealcall route")
        }
    }

    func add(_ route: String, _ value: Route) throws {
        var me: SecTrustedApplication?
        var status = SecTrustedApplicationCreateFromPath(nil, &me)
        guard status == errSecSuccess, let me else {
            throw SealError("cannot describe this binary for the Keychain: \(message(status))")
        }
        var access: SecAccess?
        status = SecAccessCreate("sealcall \(route)" as CFString, [me] as CFArray, &access)
        guard status == errSecSuccess, let access else {
            throw SealError("cannot create the Keychain access list: \(message(status))")
        }
        var query = baseQuery(route)
        query[kSecUseKeychain as String] = keychain
        query[kSecAttrLabel as String] = "sealcall \(route)"
        query[kSecAttrAccess as String] = access
        query[kSecValueData as String] = try encode(value)
        try check(SecItemAdd(query as CFDictionary, nil), route: route)
    }

    func update(_ route: String, _ value: Route) throws {
        var query = baseQuery(route)
        query[kSecMatchSearchList as String] = [keychain]
        let change = [kSecValueData as String: try encode(value)]
        try check(SecItemUpdate(query as CFDictionary, change as CFDictionary), route: route)
    }

    func remove(_ route: String) throws {
        var query = baseQuery(route)
        query[kSecMatchSearchList as String] = [keychain]
        try check(SecItemDelete(query as CFDictionary), route: route)
    }

    func names() throws -> [String] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
            kSecMatchSearchList as String: [keychain],
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        try check(status, route: nil)
        let items = result as? [[String: Any]] ?? []
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
    }

    private func baseQuery(_ route: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: KeychainStore.service,
            kSecAttrAccount as String: route,
        ]
    }

    private func encode(_ value: Route) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value)
    }

    private func check(_ status: OSStatus, route: String?) throws {
        let subject = route.map { "route \($0)" } ?? "the Keychain"
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            throw SealError("\(subject): not found")
        case errSecDuplicateItem:
            throw SealError("\(subject) already exists; use rotate, or remove it first")
        case errSecAuthFailed, errSecInteractionNotAllowed, errSecInvalidOwnerEdit:
            throw SealError(
                "\(subject): the Keychain refused access. The keychain is locked, or this binary is not "
                    + "the signed sealcall build that created the item. Deny any Keychain dialog you did not expect."
            )
        default:
            throw SealError("\(subject): \(message(status))")
        }
    }
}

private func message(_ status: OSStatus) -> String {
    (SecCopyErrorMessageString(status, nil) as String?) ?? "OSStatus \(status)"
}
