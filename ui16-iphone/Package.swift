// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "UI16Phone",
    platforms: [.iOS(.v17)],
    products: [
        .executable(name: "UI16Phone", targets: ["UI16Phone"]),
        .library(name: "UI16Controller", targets: ["UI16Controller"])
    ],
    targets: [
        .target(name: "UI16Controller", path: "Sources/UI16Controller", exclude: ["App"]),
        .executableTarget(name: "UI16Phone", dependencies: ["UI16Controller"], path: "Sources/UI16Controller/App"),
        .testTarget(name: "UI16ProtocolTests", dependencies: ["UI16Controller"], path: "Tests")
    ]
)
