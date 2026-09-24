// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HomefieldCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "HomefieldCore", targets: ["HomefieldCore"]),
    ],
    targets: [
        .target(name: "HomefieldCore"),
        .testTarget(name: "HomefieldCoreTests", dependencies: ["HomefieldCore"]),
    ]
)
