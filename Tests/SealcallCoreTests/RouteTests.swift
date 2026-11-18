import Foundation
import Testing
@testable import SealcallCore

struct RouteTests {
    static let valid = Route(
        key: "sk-test-123456", host: "api.example.com", header: "Authorization: Bearer {key}",
        allow: ["GET /v1/**"], callerHeaders: ["X-Request-Id"])

    func with(_ change: (inout Route) -> Void) -> Route {
        var route = RouteTests.valid
        change(&route)
        return route
    }

    @Test func validRoutePasses() throws {
        try RouteTests.valid.validate()
    }

    @Test func rendersKeyHeader() throws {
        let header = try RouteTests.valid.keyHeader()
        #expect(header.name == "Authorization")
        #expect(header.value == "Bearer sk-test-123456")
    }

    @Test func customKeyHeader() throws {
        let route = with { $0.header = "x-api-key:{key}" }
        try route.validate()
        #expect(try route.keyHeader().value == "sk-test-123456")
    }

    @Test(arguments: [
        RouteTests.valid.withKey(""),
        RouteTests.valid.withKey("has space"),
        RouteTests.valid.withKey("line\r\nX: y"),
        RouteTests.valid.withKey("caf\u{e9}"),
        RouteTests.valid.withHost("API.example.com"),
        RouteTests.valid.withHost("localhost"),
        RouteTests.valid.withHost("api.example.com:8443"),
        RouteTests.valid.withHost("evil.example/x"),
        RouteTests.valid.withHost("-a.example.com"),
        RouteTests.valid.withHeader("Authorization: Bearer"),
        RouteTests.valid.withHeader("Host: {key}"),
        RouteTests.valid.withHeader("Bad Name: {key}"),
        RouteTests.valid.withHeader("X-Key: {key}\r\nX: y"),
        RouteTests.valid.withAllow([]),
        RouteTests.valid.withAllow(["GET v1"]),
        RouteTests.valid.withCallerHeaders(["Authorization"]),
        RouteTests.valid.withCallerHeaders(["cookie"]),
        RouteTests.valid.withCallerHeaders(["Host"]),
        RouteTests.valid.withCallerHeaders(["authorization"]),
        RouteTests.valid.withCallerHeaders(["Bad Name"]),
    ])
    func rejects(route: Route) {
        #expect(throws: SealError.self) { try route.validate() }
    }

    @Test func callerHeadersAreCaseInsensitive() {
        #expect(RouteTests.valid.allowsCallerHeader("content-type"))
        #expect(RouteTests.valid.allowsCallerHeader("x-request-id"))
        #expect(!RouteTests.valid.allowsCallerHeader("Authorization"))
    }

    @Test func roundTripsAsJSON() throws {
        let data = try JSONEncoder().encode(RouteTests.valid)
        #expect(try JSONDecoder().decode(Route.self, from: data) == RouteTests.valid)
    }
}

extension Route: CustomTestStringConvertible {
    public var testDescription: String { "\(host) \(header) \(allow) \(callerHeaders)" }

    func withKey(_ value: String) -> Route { var r = self; r.key = value; return r }
    func withHost(_ value: String) -> Route { var r = self; r.host = value; return r }
    func withHeader(_ value: String) -> Route { var r = self; r.header = value; return r }
    func withAllow(_ value: [String]) -> Route { var r = self; r.allow = value; return r }
    func withCallerHeaders(_ value: [String]) -> Route { var r = self; r.callerHeaders = value; return r }
}
