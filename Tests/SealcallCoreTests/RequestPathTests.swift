import Testing
@testable import SealcallCore

struct RequestPathTests {
    @Test func splitsQuery() throws {
        let path = try RequestPath("/v1/items?limit=10&q=a%20b")
        #expect(path.path == "/v1/items")
        #expect(path.query == "limit=10&q=a%20b")
        #expect(path.segments == ["v1", "items"])
    }

    @Test(arguments: ["/", "/a/b/", "/a:b@c", "/files/a%20b", "/x?y=/z?w", "/r?url=https%3A%2F%2Fa.example%2Fb.c"])
    func accepts(raw: String) throws {
        _ = try RequestPath(raw)
    }

    @Test(arguments: [
        "https://evil.example/x",
        "evil.example/x",
        "//evil.example/x",
        "/a//b",
        "/a/../b",
        "/a/./b",
        "/..",
        "/a/%2e%2e/b",
        "/a%2Fb",
        "/a%5cb",
        "/a%00",
        "/a?b=%00",
        "/a?b=c d",
        "/a%zz",
        "/a%2",
        "/a b",
        "/a\\b",
        "/a#frag",
        "/caf\u{e9}",
        "/a\r\nHost: evil",
    ])
    func rejects(raw: String) {
        #expect(throws: SealError.self) { try RequestPath(raw) }
    }
}
