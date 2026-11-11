// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "SyncBoxCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "SyncBoxCore", targets: ["SyncBoxCore"])],
    targets: [
        .target(name: "SyncBoxCore", path: "SyncBox/Core"),
        .testTarget(name: "SyncBoxCoreTests", dependencies: ["SyncBoxCore"], path: "Tests")
    ]
)
