import Foundation

public protocol RouteStore: Sendable {
    func read(_ route: String) throws -> Route
    func add(_ route: String, _ value: Route) throws
    func update(_ route: String, _ value: Route) throws
    func remove(_ route: String) throws
    func names() throws -> [String]
}

public protocol HTTPClient: Sendable {
    func send(_ request: URLRequest) async throws -> (status: Int, body: Data)
}

public protocol Presence: Sendable {
    func confirm(_ reason: String) async throws
}

public protocol AuditLog: Sendable {
    func record(route: String, method: String, path: String, outcome: String)
}

public struct CallRequest: Sendable {
    public var route: String
    public var method: String
    public var path: String
    public var headers: [String]
    public var body: Data?

    public init(route: String, method: String, path: String, headers: [String] = [], body: Data? = nil) {
        self.route = route
        self.method = method
        self.path = path
        self.headers = headers
        self.body = body
    }
}

public struct RouteSummary: Equatable, Sendable {
    public let name: String
    public let host: String
    public let allow: [String]
    public let callerHeaders: [String]
}

public struct Broker: Sendable {
    let store: RouteStore
    let http: HTTPClient
    let presence: Presence
    let audit: AuditLog

    public init(store: RouteStore, http: HTTPClient, presence: Presence, audit: AuditLog) {
        self.store = store
        self.http = http
        self.presence = presence
        self.audit = audit
    }

    public func call(_ call: CallRequest) async throws -> (status: Int, body: Data) {
        let path = try RequestPath(call.path)
        let route = try store.read(call.route)
        guard try route.rules().contains(where: { $0.matches(method: call.method, path: path) }) else {
            throw SealError("route \(call.route) does not allow \(call.method) \(path.path)")
        }
        let request = try buildRequest(route: route, call: call, path: path)
        let response: (status: Int, body: Data)
        do {
            response = try await http.send(request)
        } catch {
            audit.record(route: call.route, method: call.method, path: path.path, outcome: "error")
            throw SealError("request failed: \(scrubText(error.localizedDescription, secret: route.key))")
        }
        audit.record(route: call.route, method: call.method, path: path.path, outcome: String(response.status))
        return (response.status, scrub(response.body, secret: route.key))
    }

    public func add(_ name: String, _ route: Route) async throws {
        try checkRouteName(name)
        try route.validate()
        try await presence.confirm("add route \(name) for \(route.host)")
        try store.add(name, route)
    }

    public func rotate(_ name: String, key: String) async throws {
        var route = try store.read(name)
        route.key = key
        try route.validate()
        try await presence.confirm("replace the key of route \(name) for \(route.host)")
        try store.update(name, route)
    }

    public func remove(_ name: String) async throws {
        let route = try store.read(name)
        try await presence.confirm("remove route \(name) for \(route.host)")
        try store.remove(name)
    }

    public func routes() throws -> [RouteSummary] {
        try store.names().sorted().map { name in
            let route = try store.read(name)
            return RouteSummary(name: name, host: route.host, allow: route.allow, callerHeaders: route.callerHeaders)
        }
    }

    private func buildRequest(route: Route, call: CallRequest, path: RequestPath) throws -> URLRequest {
        var components = URLComponents()
        components.scheme = "https"
        components.host = route.host
        components.percentEncodedPath = path.path
        components.percentEncodedQuery = path.query
        guard let url = components.url else {
            throw SealError("cannot build a URL for \(route.host)\(call.path)")
        }
        var request = URLRequest(url: url)
        request.httpMethod = call.method
        request.httpBody = call.body
        for raw in call.headers {
            let (name, value) = try parseHeader(raw)
            guard route.allowsCallerHeader(name) else {
                throw SealError("header \(name) is not allowed on route \(call.route)")
            }
            request.setValue(value, forHTTPHeaderField: name)
        }
        let key = try route.keyHeader()
        request.setValue(key.value, forHTTPHeaderField: key.name)
        return request
    }
}

func scrubText(_ text: String, secret: String) -> String {
    String(decoding: scrub(Data(text.utf8), secret: secret), as: UTF8.self)
}
