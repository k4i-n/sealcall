import Foundation
import Testing
@testable import SealcallCore

final class Box<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func get() -> Value { lock.withLock { value } }
    func set(_ change: (inout Value) -> Void) { lock.withLock { change(&value) } }
}

struct FakeStore: RouteStore {
    let routes = Box<[String: Route]>([:])

    func read(_ route: String) throws -> Route {
        guard let value = routes.get()[route] else { throw SealError("route \(route): not found") }
        return value
    }

    func add(_ route: String, _ value: Route) throws {
        guard routes.get()[route] == nil else { throw SealError("exists") }
        routes.set { $0[route] = value }
    }

    func update(_ route: String, _ value: Route) throws {
        routes.set { $0[route] = value }
    }

    func remove(_ route: String) throws {
        routes.set { $0[route] = nil }
    }

    func names() throws -> [String] {
        Array(routes.get().keys)
    }
}

struct FakeHTTP: HTTPClient {
    let sent = Box<[URLRequest]>([])
    let response: (status: Int, body: Data)?

    func send(_ request: URLRequest) async throws -> (status: Int, body: Data) {
        sent.set { $0.append(request) }
        guard let response else { throw SealError("offline \(request.value(forHTTPHeaderField: "Authorization") ?? "")") }
        return response
    }
}

struct FakePresence: Presence {
    let confirmed: Bool
    let reasons = Box<[String]>([])

    func confirm(_ reason: String) async throws {
        reasons.set { $0.append(reason) }
        guard confirmed else { throw SealError("not confirmed") }
    }
}

struct FakeAudit: AuditLog {
    let lines = Box<[String]>([])

    func record(route: String, method: String, path: String, outcome: String) {
        lines.set { $0.append("\(route) \(method) \(path) \(outcome)") }
    }
}

struct Fixture {
    let store = FakeStore()
    let http: FakeHTTP
    let presence: FakePresence
    let audit = FakeAudit()
    var broker: Broker { Broker(store: store, http: http, presence: presence, audit: audit) }

    init(body: String = "ok", status: Int = 200, offline: Bool = false, confirmed: Bool = true) {
        http = FakeHTTP(response: offline ? nil : (status, Data(body.utf8)))
        presence = FakePresence(confirmed: confirmed)
        store.routes.set { $0["api"] = RouteTests.valid }
    }
}

struct BrokerTests {
    @Test func callBuildsTheRequest() async throws {
        let f = Fixture()
        f.store.routes.set { $0["api"]?.allow = ["POST /v1/**"] }
        let request = CallRequest(
            route: "api", method: "POST", path: "/v1/items?limit=2",
            headers: ["Content-Type: application/json", "x-request-id: 7"], body: Data("{}".utf8))
        let response = try await f.broker.call(request)
        #expect(response.status == 200)
        let sent = try #require(f.http.sent.get().first)
        #expect(sent.url?.absoluteString == "https://api.example.com/v1/items?limit=2")
        #expect(sent.httpMethod == "POST")
        #expect(sent.httpBody == Data("{}".utf8))
        #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer sk-test-123456")
        #expect(sent.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(sent.value(forHTTPHeaderField: "X-Request-Id") == "7")
        #expect(f.audit.lines.get() == ["api POST /v1/items 200"])
    }

    @Test func callScrubsTheKeyFromTheBody() async throws {
        let f = Fixture(body: "token=sk-test-123456;")
        let response = try await f.broker.call(CallRequest(route: "api", method: "GET", path: "/v1/me"))
        #expect(String(decoding: response.body, as: UTF8.self) == "token=<redacted>;")
    }

    @Test func callReturnsErrorStatusAsIs() async throws {
        let f = Fixture(body: "nope", status: 403)
        let response = try await f.broker.call(CallRequest(route: "api", method: "GET", path: "/v1/me"))
        #expect(response.status == 403)
        #expect(f.audit.lines.get() == ["api GET /v1/me 403"])
    }

    @Test func callRejectsDisallowedRequestsWithoutSending() async {
        let f = Fixture()
        for (method, path) in [("POST", "/v1/me"), ("GET", "/v2/me"), ("GET", "/v1/../admin")] {
            await #expect(throws: SealError.self) {
                _ = try await f.broker.call(CallRequest(route: "api", method: method, path: path))
            }
        }
        #expect(f.http.sent.get().isEmpty)
        #expect(f.audit.lines.get().isEmpty)
    }

    @Test(arguments: ["Authorization: Bearer mine", "Host: evil.example", "Cookie: a=b", "X-Other: 1"])
    func callRejectsHeadersOutsideTheAllowlist(header: String) async {
        let f = Fixture()
        await #expect(throws: SealError.self) {
            _ = try await f.broker.call(CallRequest(route: "api", method: "GET", path: "/v1/me", headers: [header]))
        }
        #expect(f.http.sent.get().isEmpty)
    }

    @Test func callFailsForUnknownRoute() async {
        let f = Fixture()
        await #expect(throws: SealError("route nope: not found")) {
            _ = try await f.broker.call(CallRequest(route: "nope", method: "GET", path: "/v1/me"))
        }
    }

    @Test func transportErrorsAreScrubbedAndAudited() async throws {
        let f = Fixture(offline: true)
        let error = await #expect(throws: SealError.self) {
            _ = try await f.broker.call(CallRequest(route: "api", method: "GET", path: "/v1/me"))
        }
        #expect(error?.description.contains("sk-test-123456") == false)
        #expect(error?.description.contains("<redacted>") == true)
        #expect(f.audit.lines.get() == ["api GET /v1/me error"])
    }

    @Test func addNeedsPresence() async throws {
        let f = Fixture()
        let route = RouteTests.valid.withHost("api.other.com")
        try await f.broker.add("other", route)
        #expect(f.store.routes.get()["other"] == route)
        #expect(f.presence.reasons.get() == ["add route other for api.other.com"])
    }

    @Test func addStoresNothingWhenNotConfirmed() async {
        let f = Fixture(confirmed: false)
        await #expect(throws: SealError.self) { try await f.broker.add("other", RouteTests.valid) }
        #expect(f.store.routes.get()["other"] == nil)
    }

    @Test func addValidatesBeforeAskingForPresence() async {
        let f = Fixture()
        await #expect(throws: SealError.self) { try await f.broker.add("other", RouteTests.valid.withHost("bad host")) }
        await #expect(throws: SealError.self) { try await f.broker.add("Bad", RouteTests.valid) }
        #expect(f.presence.reasons.get().isEmpty)
    }

    @Test func rotateKeepsTheBindingAndChangesTheKey() async throws {
        let f = Fixture()
        try await f.broker.rotate("api", key: "sk-new-999")
        #expect(f.store.routes.get()["api"] == RouteTests.valid.withKey("sk-new-999"))
    }

    @Test func rotateAndRemoveStopWhenNotConfirmed() async {
        let f = Fixture(confirmed: false)
        await #expect(throws: SealError.self) { try await f.broker.rotate("api", key: "sk-new-999") }
        await #expect(throws: SealError.self) { try await f.broker.remove("api") }
        #expect(f.store.routes.get()["api"] == RouteTests.valid)
    }

    @Test func removeDeletesAfterPresence() async throws {
        let f = Fixture()
        try await f.broker.remove("api")
        #expect(f.store.routes.get()["api"] == nil)
        #expect(f.presence.reasons.get() == ["remove route api for api.example.com"])
    }

    @Test func routesNeverCarryTheKey() throws {
        let f = Fixture()
        f.store.routes.set { $0["b"] = RouteTests.valid.withHost("b.example.com") }
        let routes = try f.broker.routes()
        #expect(routes.map(\.name) == ["api", "b"])
        #expect(routes[0] == RouteSummary(
            name: "api", host: "api.example.com", allow: ["GET /v1/**"], callerHeaders: ["X-Request-Id"]))
        #expect(!String(describing: routes).contains("sk-test"))
    }
}
