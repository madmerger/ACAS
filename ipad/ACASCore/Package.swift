// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ACASCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "ACASCore", targets: ["ACASCore"])],
    targets: [
        .target(name: "ACASCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "ACASCoreTests", dependencies: ["ACASCore"]),
    ]
)
