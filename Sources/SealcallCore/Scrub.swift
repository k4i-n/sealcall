import Foundation

public let redacted = Data("<redacted>".utf8)

public func scrub(_ data: Data, secret: String) -> Data {
    let needle = Data(secret.utf8)
    guard !needle.isEmpty else { return data }
    var output = Data()
    var rest = data[...]
    while let found = rest.range(of: needle) {
        output.append(rest[..<found.lowerBound])
        output.append(redacted)
        rest = rest[found.upperBound...]
    }
    output.append(rest)
    return output
}
