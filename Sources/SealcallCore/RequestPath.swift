public struct RequestPath: Equatable, Sendable {
    public let path: String
    public let query: String?
    public let segments: [String]

    public init(_ raw: String) throws {
        guard raw.hasPrefix("/") else {
            throw SealError("path \"\(raw)\" must start with /")
        }
        let parts = raw.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let path = String(parts[0])
        let query = parts.count == 2 ? String(parts[1]) : nil
        try RequestPath.checkChars(path, allowed: pathChars, forbidEscapes: forbiddenPathEscapes, raw: raw)
        if let query {
            try RequestPath.checkChars(query, allowed: queryChars, forbidEscapes: [0x00], raw: raw)
        }
        let segments = splitSegments(path)
        if segments.dropLast().contains("") {
            throw SealError("path \"\(raw)\" has an empty segment")
        }
        if segments.contains(where: { $0 == "." || $0 == ".." }) {
            throw SealError("path \"\(raw)\" has a dot segment")
        }
        self.path = path
        self.query = query
        self.segments = segments
    }

    private static func checkChars(_ text: String, allowed: Set<UInt8>, forbidEscapes: Set<UInt8>, raw: String) throws {
        let bytes = Array(text.utf8)
        var i = 0
        while i < bytes.count {
            let byte = bytes[i]
            if byte != UInt8(ascii: "%") {
                guard allowed.contains(byte) else {
                    throw SealError("path \"\(raw)\" has a character that must be percent-encoded")
                }
                i += 1
                continue
            }
            guard i + 2 < bytes.count, let value = hexByte(bytes[i + 1], bytes[i + 2]) else {
                throw SealError("path \"\(raw)\" has a bad percent escape")
            }
            if forbidEscapes.contains(value) {
                throw SealError("path \"\(raw)\" encodes a character that is not allowed there")
            }
            i += 3
        }
    }
}

private let forbiddenPathEscapes: Set<UInt8> = [0x00, UInt8(ascii: "/"), UInt8(ascii: "\\"), UInt8(ascii: ".")]

private let unreserved = Set("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~".utf8)
private let subDelims = Set("!$&'()*+,;=".utf8)
private let pathChars = unreserved.union(subDelims).union(":@/".utf8)
private let queryChars = pathChars.union("?".utf8)

private func hexByte(_ high: UInt8, _ low: UInt8) -> UInt8? {
    guard let h = hexValue(high), let l = hexValue(low) else { return nil }
    return h << 4 | l
}

private func hexValue(_ c: UInt8) -> UInt8? {
    switch c {
    case UInt8(ascii: "0")...UInt8(ascii: "9"): return c - UInt8(ascii: "0")
    case UInt8(ascii: "a")...UInt8(ascii: "f"): return c - UInt8(ascii: "a") + 10
    case UInt8(ascii: "A")...UInt8(ascii: "F"): return c - UInt8(ascii: "A") + 10
    default: return nil
    }
}
