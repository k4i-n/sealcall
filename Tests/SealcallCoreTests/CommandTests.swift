import Testing
@testable import SealcallCore

struct CommandTests {
    @Test func parsesCall() throws {
        let command = try Command.parse([
            "call", "linear", "POST", "/graphql", "--data", "q.json", "-H", "Content-Type: application/json", "-o", "out.json",
        ])
        #expect(command == .call(CallArgs(
            route: "linear", method: "POST", path: "/graphql", data: "q.json",
            headers: ["Content-Type: application/json"], output: "out.json")))
    }

    @Test func parsesCallWithStdinBody() throws {
        let command = try Command.parse(["call", "x", "PUT", "/a", "-d", "-"])
        #expect(command == .call(CallArgs(route: "x", method: "PUT", path: "/a", data: "-")))
    }

    @Test func parsesAdd() throws {
        let command = try Command.parse([
            "add", "cloudflare", "--host", "api.cloudflare.com", "--header", "Authorization: Bearer {key}",
            "--allow", "GET /client/v4/**", "--allow", "POST /client/v4/zones", "--caller-header", "X-Auth", "--stdin",
        ])
        #expect(command == .add(AddArgs(
            route: "cloudflare", host: "api.cloudflare.com", header: "Authorization: Bearer {key}",
            allow: ["GET /client/v4/**", "POST /client/v4/zones"], callerHeaders: ["X-Auth"], stdin: true)))
    }

    @Test func parsesOthers() throws {
        #expect(try Command.parse(["rotate", "a"]) == .rotate(route: "a", stdin: false))
        #expect(try Command.parse(["rotate", "a", "--stdin"]) == .rotate(route: "a", stdin: true))
        #expect(try Command.parse(["remove", "a"]) == .remove(route: "a"))
        #expect(try Command.parse(["routes"]) == .routes)
        #expect(try Command.parse([]) == .help)
        #expect(try Command.parse(["--help"]) == .help)
    }

    @Test(arguments: [
        ["show", "a"],
        ["get", "a"],
        ["call", "a", "get", "/x"],
        ["call", "a", "GET"],
        ["call", "a", "GET", "/x", "--data"],
        ["call", "a", "GET", "/x", "--data", "a", "--data", "b"],
        ["call", "a", "GET", "/x", "--key"],
        ["call", "A", "GET", "/x"],
        ["call", "../a", "GET", "/x"],
        ["add", "a", "--host", "h.example"],
        ["add", "a", "--host", "h.example", "--host", "i.example", "--header", "X: {key}"],
        ["rotate", "a", "b"],
        ["remove"],
        ["routes", "--all"],
    ])
    func rejects(args: [String]) {
        #expect(throws: SealError.self) { try Command.parse(args) }
    }
}
