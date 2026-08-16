// swift-tools-version: 5.9
import PackageDescription

// Pure, cross-platform control/protocol library for the Soundcraft Ui16.
// The SwiftUI iPhone app lives in the Xcode project (app/UI16Control.xcodeproj) and links
// this library. Keeping the library free of UIKit/SwiftUI lets `swift test` run the full
// protocol/state test suite on macOS and in CI without a simulator.
let package = Package(
    name: "UI16Controller",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "UI16Controller", targets: ["UI16Controller"])
    ],
    targets: [
        .target(name: "UI16Controller", path: "Sources/UI16Controller"),
        .testTarget(
            name: "UI16ControllerTests",
            dependencies: ["UI16Controller"],
            path: "Tests"
        )
    ]
)
