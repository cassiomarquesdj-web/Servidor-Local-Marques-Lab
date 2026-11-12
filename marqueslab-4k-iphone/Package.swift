// swift-tools-version: 5.9
import PackageDescription

// MarquesDownloadCore is deliberately free of SwiftUI, UIKit and AVFoundation:
// URL handling, media selection, the extractor contract and the queue state
// machine are pure value types, so `swift test` runs the whole suite on macOS
// and in CI without ever booting a simulator.
//
// Everything that needs the device — background URLSession transfers, the
// AVFoundation muxing and the interface — lives in app/MarquesLab4K.
let package = Package(
    name: "MarquesDownloadCore",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [
        .library(name: "MarquesDownloadCore", targets: ["MarquesDownloadCore"])
    ],
    targets: [
        .target(name: "MarquesDownloadCore", path: "Sources/MarquesDownloadCore"),
        .testTarget(
            name: "MarquesDownloadCoreTests",
            dependencies: ["MarquesDownloadCore"],
            path: "Tests/MarquesDownloadCoreTests"
        )
    ]
)
