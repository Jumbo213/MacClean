// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacClean",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "MacClean", targets: ["MacClean"]), .executable(name: "MacCleanChecks", targets: ["MacCleanChecks"])],
    targets: [
        .target(name: "MacCleanCore"),
        .executableTarget(name: "MacClean", dependencies: ["MacCleanCore"]),
        .executableTarget(name: "MacCleanChecks", dependencies: ["MacCleanCore"], path: "Tests/MacCleanCoreTests")
    ]
)
