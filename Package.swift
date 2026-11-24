// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "EmiKey",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EmiKeyCore", targets: ["EmiKeyCore"])],
    targets: [
        .target(name: "EmiKeyCore", path: "Sources/EmiKeyCore"),
        .executableTarget(name: "EmiKey", dependencies: ["EmiKeyCore"], path: "Sources/EmiKey"),
        .testTarget(name: "EmiKeyCoreTests", dependencies: ["EmiKeyCore"], path: "Tests/EmiKeyCoreTests",
                    resources: [.copy("Fixtures")]),
    ]
)
