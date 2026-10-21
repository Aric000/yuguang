// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Yuguang",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Yuguang", targets: ["Yuguang"])],
    targets: [
        .target(name: "YuguangCore"),
        .executableTarget(name: "Yuguang", dependencies: ["YuguangCore"], resources: [.copy("Resources/Teams")]),
        .testTarget(name: "YuguangCoreTests", dependencies: ["YuguangCore"])
    ]
)
