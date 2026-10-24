// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ShareXMac",
    platforms: [.macOS(.v13)],
    products: [.library(name: "ShareXMacCore", targets: ["ShareXMacCore"])],
    targets: [
        .target(name: "ShareXMacCore"),
        .testTarget(name: "ShareXMacCoreTests", dependencies: ["ShareXMacCore"])
    ]
)
