public struct CallArgs: Equatable, Sendable {
    public var route: String
    public var method: String
    public var path: String
    public var data: String?
    public var headers: [String] = []
    public var output: String?
}

public struct AddArgs: Equatable, Sendable {
    public var route: String
    public var host: String
    public var header: String
    public var allow: [String]
    public var callerHeaders: [String]
    public var stdin: Bool
}

public enum Command: Equatable, Sendable {
    case call(CallArgs)
    case add(AddArgs)
    case rotate(route: String, stdin: Bool)
    case remove(route: String)
    case routes
    case help

    public static func parse(_ args: [String]) throws -> Command {
        guard let name = args.first else { return .help }
        var rest = Arguments(Array(args.dropFirst()))
        switch name {
        case "call":
            return .call(try parseCall(&rest))
        case "add":
            return .add(try parseAdd(&rest))
        case "rotate":
            let route = try rest.route()
            let stdin = try rest.flags(["--stdin"]).contains("--stdin")
            try rest.end()
            return .rotate(route: route, stdin: stdin)
        case "remove":
            let route = try rest.route()
            try rest.end()
            return .remove(route: route)
        case "routes":
            try rest.end()
            return .routes
        case "help", "-h", "--help":
            return .help
        default:
            throw SealError("unknown command \"\(name)\"")
        }
    }

    private static func parseCall(_ rest: inout Arguments) throws -> CallArgs {
        var call = CallArgs(route: try rest.route(), method: try rest.positional("METHOD"), path: try rest.positional("path"))
        guard isMethod(call.method) else {
            throw SealError("method must be uppercase letters, such as GET")
        }
        while let option = rest.next() {
            switch option {
            case "--data", "-d":
                guard call.data == nil else { throw SealError("--data given twice") }
                call.data = try rest.value(for: option)
            case "-H", "--header":
                call.headers.append(try rest.value(for: option))
            case "-o", "--output":
                guard call.output == nil else { throw SealError("-o given twice") }
                call.output = try rest.value(for: option)
            default:
                throw SealError("unknown option \"\(option)\" for call")
            }
        }
        return call
    }

    private static func parseAdd(_ rest: inout Arguments) throws -> AddArgs {
        let route = try rest.route()
        var host: String?
        var header: String?
        var add = AddArgs(route: route, host: "", header: "", allow: [], callerHeaders: [], stdin: false)
        while let option = rest.next() {
            switch option {
            case "--host":
                guard host == nil else { throw SealError("--host given twice") }
                host = try rest.value(for: option)
            case "--header":
                guard header == nil else { throw SealError("--header given twice") }
                header = try rest.value(for: option)
            case "--allow":
                add.allow.append(try rest.value(for: option))
            case "--caller-header":
                add.callerHeaders.append(try rest.value(for: option))
            case "--stdin":
                add.stdin = true
            default:
                throw SealError("unknown option \"\(option)\" for add")
            }
        }
        guard let host, let header else {
            throw SealError("add needs --host and --header")
        }
        add.host = host
        add.header = header
        return add
    }
}

struct Arguments {
    private var items: [String]

    init(_ items: [String]) {
        self.items = items
    }

    mutating func next() -> String? {
        items.isEmpty ? nil : items.removeFirst()
    }

    mutating func positional(_ name: String) throws -> String {
        guard let item = next(), !item.hasPrefix("-") else {
            throw SealError("missing \(name)")
        }
        return item
    }

    mutating func route() throws -> String {
        let name = try positional("route name")
        try checkRouteName(name)
        return name
    }

    mutating func value(for option: String) throws -> String {
        guard let item = next() else {
            throw SealError("\(option) needs a value")
        }
        return item
    }

    mutating func flags(_ known: Set<String>) throws -> Set<String> {
        var found: Set<String> = []
        while let item = items.first, known.contains(item) {
            found.insert(item)
            items.removeFirst()
        }
        return found
    }

    func end() throws {
        if let extra = items.first {
            throw SealError("unexpected argument \"\(extra)\"")
        }
    }
}

public func checkRouteName(_ name: String) throws {
    let chars = Set("abcdefghijklmnopqrstuvwxyz0123456789-_".utf8)
    guard (1...64).contains(name.utf8.count), name.utf8.allSatisfy({ chars.contains($0) }), !name.hasPrefix("-") else {
        throw SealError("route name \"\(name)\" must be 1-64 of a-z 0-9 - _")
    }
}
