// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "quint-connect-swift",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "QuintConnect", targets: ["QuintConnect"])
    ],
    targets: [
        .target(name: "QuintConnect"),
        .testTarget(
            name: "QuintConnectTests",
            dependencies: ["QuintConnect"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
