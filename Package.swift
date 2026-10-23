// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuBarStudio",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MenuBarStudio", targets: ["MenuBarStudio"])],
    targets: [
        .target(name: "MenuBarCore", resources: [.process("Resources")]),
        .executableTarget(name: "MenuBarStudio", dependencies: ["MenuBarCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["MenuBarCore"], path: "Tests/MenuBarCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
