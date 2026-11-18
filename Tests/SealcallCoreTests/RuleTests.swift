import Testing
@testable import SealcallCore

struct RuleTests {
    func allows(_ rule: String, _ method: String, _ path: String) throws -> Bool {
        try Rule(rule).matches(method: method, path: RequestPath(path))
    }

    @Test(arguments: [
        ("GET /client/v4/**", "GET", "/client/v4/zones", true),
        ("GET /client/v4/**", "GET", "/client/v4", true),
        ("GET /client/v4/**", "GET", "/client/v4/zones/abc/dns_records", true),
        ("GET /client/v4/**", "POST", "/client/v4/zones", false),
        ("GET /client/v4/**", "GET", "/client/v5/zones", false),
        ("GET /client/v4/**", "GET", "/client/v4x", false),
        ("POST /graphql", "POST", "/graphql", true),
        ("POST /graphql", "POST", "/graphql/x", false),
        ("POST /graphql", "POST", "/graphql?x=1", true),
        ("GET /repos/*/issues", "GET", "/repos/sealcall/issues", true),
        ("GET /repos/*/issues", "GET", "/repos/a/b/issues", false),
        ("GET /files/*.json", "GET", "/files/a.json", true),
        ("GET /files/*.json", "GET", "/files/a.txt", false),
        ("GET /a/**/z", "GET", "/a/z", true),
        ("GET /a/**/z", "GET", "/a/b/c/z", true),
        ("GET /a/**/z", "GET", "/a/b/c", false),
    ])
    func matching(rule: String, method: String, path: String, expected: Bool) throws {
        #expect(try allows(rule, method, path) == expected)
    }

    @Test(arguments: ["GET", "get /x", "GET x", "GET /a/b**", "GET /x extra", "G3T /x"])
    func rejectsBadRules(rule: String) {
        #expect(throws: SealError.self) { try Rule(rule) }
    }
}
