// swift-tools-version:5.9
import PackageDescription
import Foundation

// with xcode installed, `swift test` uses the real XCTest. with command line
// tools only there is no XCTest, so SPACEBAR_XCTEST_SHIM=1 swaps in a tiny
// look-alike (Tests/XCTestShim) and runs the same test files through
// `swift run spacebar-tests`. `make test` picks automatically.
let useShim = ProcessInfo.processInfo.environment["SPACEBAR_XCTEST_SHIM"] == "1"

var targets: [Target] = [
    .target(name: "SpacebarKit", linkerSettings: [.linkedLibrary("sqlite3")]),
    .executableTarget(name: "spacebar-cli", dependencies: ["SpacebarKit"]),
]
var products: [Product] = [
    .library(name: "SpacebarKit", targets: ["SpacebarKit"]),
    .executable(name: "spacebar-cli", targets: ["spacebar-cli"]),
]

if useShim {
    targets += [
        .target(name: "XCTest", path: "Tests/XCTestShim"),
        .executableTarget(name: "spacebar-tests", dependencies: ["SpacebarKit", "XCTest"],
                          path: "Tests/SpacebarKitTests",
                          linkerSettings: [.linkedFramework("JavaScriptCore")]),
    ]
    products.append(.executable(name: "spacebar-tests", targets: ["spacebar-tests"]))
} else {
    targets.append(.testTarget(name: "SpacebarKitTests", dependencies: ["SpacebarKit"],
                               exclude: ["Runner.swift"],
                               linkerSettings: [.linkedFramework("JavaScriptCore")]))
}

let package = Package(
    name: "SpacebarKit",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
