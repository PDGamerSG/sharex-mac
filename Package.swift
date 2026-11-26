// swift-tools-version: 6.0
import PackageDescription

#if os(Linux)
let package = Package(
    name: "ShareXLinux",
    products: [
        .library(name: "ShareXCore", targets: ["ShareXCore"]),
        .library(name: "ShareXLinuxCore", targets: ["ShareXLinuxCore"]),
        .executable(name: "ShareXLinux", targets: ["ShareXLinux"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"]), .yum(["sqlite-devel"])]),
        .target(name: "ShareXCore", dependencies: ["CSQLite"]),
        .target(name: "ShareXLinuxCore", dependencies: ["ShareXCore"]),
        .executableTarget(name: "ShareXLinux", dependencies: ["ShareXLinuxCore"], resources: [.copy("Desktop")]),
        .testTarget(name: "ShareXCoreTests", dependencies: [
            "ShareXCore",
            "CSQLite",
            .product(name: "Testing", package: "swift-testing")
        ]),
        .testTarget(name: "ShareXLinuxTests", dependencies: [
            "ShareXLinuxCore",
            .product(name: "Testing", package: "swift-testing")
        ])
    ]
)
#else
let package = Package(
    name: "ShareXMac",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "ShareXCore", targets: ["ShareXCore"]),
        .library(name: "ShareXMacCore", targets: ["ShareXMacCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0")
    ],
    targets: [
        .target(name: "ShareXCore"),
        .target(name: "ShareXMacCore", dependencies: ["ShareXCore"]),
        .executableTarget(name: "ShareXMac", dependencies: ["ShareXMacCore"]),
        .testTarget(name: "ShareXCoreTests", dependencies: [
            "ShareXCore",
            .product(name: "Testing", package: "swift-testing")
        ]),
        .testTarget(name: "ShareXMacCoreTests", dependencies: [
            "ShareXMacCore",
            .product(name: "Testing", package: "swift-testing")
        ]),
        .testTarget(name: "ShareXMacTests", dependencies: [
            "ShareXMac",
            .product(name: "Testing", package: "swift-testing")
        ])
    ]
)
#endif
