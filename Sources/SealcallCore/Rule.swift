public struct Rule: Equatable, Sendable {
    public let method: String
    public let segments: [String]

    public init(_ text: String) throws {
        let parts = text.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 2 else {
            throw SealError("rule \"\(text)\": want \"METHOD /path/glob\"")
        }
        let method = String(parts[0])
        guard isMethod(method) else {
            throw SealError("rule \"\(text)\": method must be uppercase letters")
        }
        let pattern = String(parts[1])
        guard pattern.hasPrefix("/") else {
            throw SealError("rule \"\(text)\": path must start with /")
        }
        let segments = splitSegments(pattern)
        guard !segments.contains(where: { $0.contains("**") && $0 != "**" }) else {
            throw SealError("rule \"\(text)\": ** must be a whole path segment")
        }
        self.method = method
        self.segments = segments
    }

    public func matches(method: String, path: RequestPath) -> Bool {
        method == self.method && Rule.match(segments[...], path.segments[...])
    }

    private static func match(_ pattern: ArraySlice<String>, _ path: ArraySlice<String>) -> Bool {
        guard let head = pattern.first else { return path.isEmpty }
        if head == "**" {
            return (path.startIndex...path.endIndex).contains { match(pattern.dropFirst(), path[$0...]) }
        }
        guard let segment = path.first, !(head == "*" && segment.isEmpty),
              segmentMatches(Array(head.utf8)[...], Array(segment.utf8)[...])
        else {
            return false
        }
        return match(pattern.dropFirst(), path.dropFirst())
    }

    private static func segmentMatches(_ pattern: ArraySlice<UInt8>, _ text: ArraySlice<UInt8>) -> Bool {
        guard let head = pattern.first else { return text.isEmpty }
        if head == UInt8(ascii: "*") {
            return (text.startIndex...text.endIndex).contains { segmentMatches(pattern.dropFirst(), text[$0...]) }
        }
        guard let first = text.first, first == head else { return false }
        return segmentMatches(pattern.dropFirst(), text.dropFirst())
    }
}

func isMethod(_ text: String) -> Bool {
    !text.isEmpty && text.utf8.allSatisfy { $0 >= UInt8(ascii: "A") && $0 <= UInt8(ascii: "Z") }
}

func splitSegments(_ path: String) -> [String] {
    path.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
}
