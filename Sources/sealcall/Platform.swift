import Foundation
import LocalAuthentication
import SealcallCore

final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}

struct URLSessionClient: HTTPClient {
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        let config = URLSessionConfiguration.ephemeral
        config.httpCookieStorage = nil
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw SealError("the response is not HTTP")
        }
        return (http.statusCode, data)
    }
}

struct LocalPresence: Presence {
    func confirm(_ reason: String) async throws {
        let context = LAContext()
        do {
            _ = try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)
        } catch {
            throw SealError("not confirmed: \(error.localizedDescription)")
        }
    }
}

struct FileAudit: AuditLog {
    let url: URL

    func record(route: String, method: String, path: String, outcome: String) {
        let time = ISO8601DateFormatter().string(from: Date())
        let line = "\(time) \(route) \(method) \(path) \(outcome)\n"
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(line.utf8))
        } catch {
            FileHandle.standardError.write(Data("sealcall: audit log: \(error.localizedDescription)\n".utf8))
        }
    }
}
