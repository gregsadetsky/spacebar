// entry point for the XCTest shim runner (command line tools only, no xcode).
// excluded from the real test target; see Package.swift.
import XCTest
import Foundation

@main
struct Runner {
    static func main() {
        exit(ShimRunner.runAll())
    }
}
