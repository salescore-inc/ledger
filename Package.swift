// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "LedgerCLI",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "ledger", targets: ["LedgerCLI"])],
    dependencies: [.package(url: "https://github.com/apple/swift-crypto.git", exact: "4.1.0")],
    targets: [
        .executableTarget(name: "LedgerCLI", dependencies: [.product(name: "Crypto", package: "swift-crypto")], exclude: ["Append/DESIGN.md"]),
        .testTarget(name: "LedgerCLITests", dependencies: ["LedgerCLI"]),
    ]
)
