public struct Route: Codable, Equatable, Sendable {
    public var key: String
    public var host: String
    public var header: String
    public var allow: [String]
    public var callerHeaders: [String]

    public init(key: String, host: String, header: String, allow: [String], callerHeaders: [String] = []) {
        self.key = key
        self.host = host
        self.header = header
        self.allow = allow
        self.callerHeaders = callerHeaders
    }

    public func validate() throws {
        try Route.checkKey(key)
        try Route.checkHost(host)
        let (name, value) = try parseHeader(header)
        guard value.contains("{key}") else {
            throw SealError("header \"\(header)\" must contain {key}")
        }
        guard !framingHeaders.contains(name.lowercased()) else {
            throw SealError("header \(name) cannot carry the key")
        }
        guard !allow.isEmpty else {
            throw SealError("a route needs at least one --allow rule")
        }
        for rule in allow {
            _ = try Rule(rule)
        }
        for extra in callerHeaders {
            guard isToken(extra) else {
                throw SealError("caller header \"\(extra)\" is not a valid header name")
            }
            let lower = extra.lowercased()
            guard !framingHeaders.contains(lower), !credentialHeaders.contains(lower), lower != name.lowercased() else {
                throw SealError("caller header \(extra) is not allowed")
            }
        }
    }

    public func keyHeader() throws -> (name: String, value: String) {
        let (name, template) = try parseHeader(header)
        return (name, template.replacingOccurrences(of: "{key}", with: key))
    }

    public func rules() throws -> [Rule] {
        try allow.map(Rule.init)
    }

    public func allowsCallerHeader(_ name: String) -> Bool {
        let lower = name.lowercased()
        return (baseCallerHeaders + callerHeaders).contains { $0.lowercased() == lower }
    }

    static func checkKey(_ key: String) throws {
        guard !key.isEmpty, key.utf8.count <= 8192 else {
            throw SealError("the key is empty or too long")
        }
        guard key.utf8.allSatisfy({ $0 > 0x20 && $0 < 0x7F }) else {
            throw SealError("the key must be printable ASCII without spaces")
        }
    }

    static func checkHost(_ host: String) throws {
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        let valid = host.utf8.count <= 253 && labels.count >= 2 && labels.allSatisfy { label in
            !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                && label.utf8.allSatisfy { hostChars.contains($0) }
        }
        guard valid else {
            throw SealError("host \"\(host)\" must be a lowercase DNS name such as api.example.com")
        }
    }
}

public let baseCallerHeaders = ["Content-Type", "Accept"]

private let framingHeaders: Set<String> = [
    "host", "content-length", "transfer-encoding", "connection", "upgrade", "te", "trailer", "expect",
]
private let credentialHeaders: Set<String> = ["authorization", "proxy-authorization", "cookie"]

private let hostChars = Set("abcdefghijklmnopqrstuvwxyz0123456789-".utf8)
private let tokenChars = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789!#$%&'*+-.^_`|~".utf8)

func isToken(_ text: String) -> Bool {
    !text.isEmpty && text.utf8.allSatisfy { tokenChars.contains($0) }
}

public func parseHeader(_ text: String) throws -> (name: String, value: String) {
    guard let colon = text.firstIndex(of: ":") else {
        throw SealError("header \"\(text)\": want \"Name: value\"")
    }
    let name = String(text[..<colon])
    let value = String(text[text.index(after: colon)...].drop { $0 == " " })
    guard isToken(name) else {
        throw SealError("header \"\(text)\": bad name")
    }
    guard value.utf8.allSatisfy({ $0 == 0x09 || ($0 >= 0x20 && $0 != 0x7F) }) else {
        throw SealError("header \(name): value has a control character")
    }
    return (name, value)
}
