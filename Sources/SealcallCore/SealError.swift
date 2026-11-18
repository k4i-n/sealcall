import Foundation

public struct SealError: LocalizedError, Equatable, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }

    public var errorDescription: String? { description }
}
