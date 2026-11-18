// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "HMLauncher",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "HMLauncherApp", targets: ["HMLauncherApp"]),
    ],
    targets: [
        .target(name: "HMLauncherCore"),
        .executableTarget(name: "HMLauncherApp", dependencies: ["HMLauncherCore"]),
        .testTarget(name: "HMLauncherCoreTests", dependencies: ["HMLauncherCore"], exclude: ["Fixtures"]), // read by path
    ],
    swiftLanguageModes: [.v5]
)
