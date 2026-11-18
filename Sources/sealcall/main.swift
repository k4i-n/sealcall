import Darwin
import Foundation
import Security
import SealcallCore

let usage = """
    usage:
      sealcall call <route> <METHOD> <path> [--data <file>|-] [-H 'Name: value']... [-o <file>]
      sealcall add <route> --host <host> --header '<Name>: <template with {key}>' --allow '<METHOD> <path glob>'...
                   [--caller-header <Name>]... [--stdin]
      sealcall rotate <route> [--stdin]
      sealcall remove <route>
      sealcall routes

    """

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("sealcall: \(message)\n".utf8))
    exit(1)
}

func readKey(stdin: Bool) throws -> String {
    if stdin {
        guard let line = readLine(strippingNewline: true), !line.isEmpty else {
            throw SealError("no key on stdin")
        }
        return line
    }
    var buffer = [CChar](repeating: 0, count: 8193)
    defer { buffer.withUnsafeMutableBytes { _ = memset_s($0.baseAddress, $0.count, 0, $0.count) } }
    guard readpassphrase("API key (hidden): ", &buffer, buffer.count, RPP_REQUIRE_TTY) != nil else {
        throw SealError("cannot read the key from the terminal; use --stdin")
    }
    let key = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    guard !key.isEmpty else { throw SealError("no key entered") }
    return key
}

func readBody(_ source: String?) throws -> Data? {
    guard let source else { return nil }
    if source == "-" {
        return FileHandle.standardInput.readDataToEndOfFile()
    }
    guard let data = FileManager.default.contents(atPath: source) else {
        throw SealError("cannot read \(source)")
    }
    return data
}

func writeOutput(_ data: Data, to path: String?) throws {
    guard let path else {
        FileHandle.standardOutput.write(data)
        return
    }
    guard FileManager.default.createFile(atPath: path, contents: data, attributes: [.posixPermissions: 0o600]) else {
        throw SealError("cannot write \(path)")
    }
}

func run(_ command: Command, broker: Broker) async throws -> Int32 {
    switch command {
    case .help:
        FileHandle.standardOutput.write(Data(usage.utf8))
    case .call(let args):
        let request = CallRequest(
            route: args.route, method: args.method, path: args.path,
            headers: args.headers, body: try readBody(args.data))
        let response = try await broker.call(request)
        try writeOutput(response.body, to: args.output)
        FileHandle.standardError.write(Data("HTTP \(response.status)\n".utf8))
        return response.status >= 400 ? 1 : 0
    case .add(let args):
        let key = try readKey(stdin: args.stdin)
        let route = Route(key: key, host: args.host, header: args.header, allow: args.allow, callerHeaders: args.callerHeaders)
        try await broker.add(args.route, route)
        print("added \(args.route) for \(args.host)")
    case .rotate(let name, let stdin):
        try await broker.rotate(name, key: try readKey(stdin: stdin))
        print("rotated \(name)")
    case .remove(let name):
        try await broker.remove(name)
        print("removed \(name)")
    case .routes:
        for route in try broker.routes() {
            let extra = route.callerHeaders.isEmpty ? "" : "  headers: \(route.callerHeaders.joined(separator: ", "))"
            print("\(route.name)  \(route.host)  \(route.allow.joined(separator: ", "))\(extra)")
        }
    }
    return 0
}

SecKeychainSetUserInteractionAllowed(false)
let home = FileManager.default.homeDirectoryForCurrentUser
let keychainPath = ProcessInfo.processInfo.environment["SEALCALL_KEYCHAIN"]
    ?? home.appendingPathComponent("Library/Keychains/login.keychain-db").path
do {
    let command = try Command.parse(Array(CommandLine.arguments.dropFirst()))
    let broker = Broker(
        store: try KeychainStore(path: keychainPath),
        http: URLSessionClient(),
        presence: LocalPresence(),
        audit: FileAudit(url: home.appendingPathComponent("Library/Logs/sealcall/audit.log")))
    exit(try await run(command, broker: broker))
} catch let error as SealError {
    fail(error.description)
} catch {
    fail(error.localizedDescription)
}
