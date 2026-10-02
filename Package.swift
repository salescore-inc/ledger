// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "ContextGraphCLI",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "contextgraph", targets: ["ContextGraphCLI"])],
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", exact: "4.1.0")],
    targets: [
        .executableTarget(name: "ContextGraphCLI", dependencies: [.product(name: "Crypto", package: "swift-crypto")], exclude: ["Append/DESIGN.md"]),
        .testTarget(name: "ContextGraphCLITests", dependencies: ["ContextGraphCLI"]),
    ]
)
