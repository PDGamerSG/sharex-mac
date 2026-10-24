// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShareXMac",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ShareXMacCore", targets: ["ShareXMacCore"])],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .target(name: "ShareXMacCore"),
        .executableTarget(name: "ShareXMac", dependencies: ["ShareXMacCore"]),
        .testTarget(name: "ShareXMacCoreTests", dependencies: [
            "ShareXMacCore",
            .product(name: "Testing", package: "swift-testing")
        ])
    ]
)
