// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "sealcall",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "SealcallCore"),
        .executableTarget(
            name: "sealcall",
            dependencies: ["SealcallCore"],
            linkerSettings: [.linkedFramework("Security"), .linkedFramework("LocalAuthentication")]
        ),
        .testTarget(name: "SealcallCoreTests", dependencies: ["SealcallCore"]),
    ]
)
