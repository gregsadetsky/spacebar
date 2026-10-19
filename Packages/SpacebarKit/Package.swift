// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "SpacebarKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpacebarKit", targets: ["SpacebarKit"]),
    ],
    targets: [
        .target(name: "SpacebarKit", linkerSettings: [.linkedLibrary("sqlite3")]),
        .testTarget(name: "SpacebarKitTests", dependencies: ["SpacebarKit"]),
    ]
)
