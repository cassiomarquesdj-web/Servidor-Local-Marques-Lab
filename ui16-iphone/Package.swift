// swift-tools-version: 5.9
import PackageDescription

// Two pure, cross-platform libraries. The SwiftUI app lives in app/UI16Control.xcodeproj
// and links both. Keeping them free of UIKit/SwiftUI lets `swift test` run the whole
// protocol/player/library suite on macOS and in CI, without a simulator.
//
// - UI16Controller: Soundcraft Ui16 protocol, state and transport.
// - ParedaoCore:    player queue, music library, playlists, EQ and polarity models.
//   ParedaoCore does not depend on UI16Controller: the player must keep working with the
//   mixer disconnected, so the two are wired together only at the app layer.
let package = Package(
    name: "UI16Controller",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "UI16Controller", targets: ["UI16Controller"]),
        .library(name: "ParedaoCore", targets: ["ParedaoCore"])
    ],
    targets: [
        .target(name: "UI16Controller", path: "Sources/UI16Controller"),
        .target(name: "ParedaoCore", path: "Sources/ParedaoCore"),
        .testTarget(
            name: "UI16ControllerTests",
            dependencies: ["UI16Controller", "ParedaoCore"],
            path: "Tests"
        )
    ]
)
