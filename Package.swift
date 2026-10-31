// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "SmixxDesktop",
    platforms: [.macOS("14.2")],
    products: [.executable(name: "SmixxDesktop", targets: ["SmixxDesktop"])],
    targets: [
        .target(name: "MixerDSP", publicHeadersPath: "include", linkerSettings: [.linkedFramework("CoreAudio")]),
        .target(name: "SmixxCore"),
        .executableTarget(name: "SmixxDesktop", dependencies: ["SmixxCore", "MixerDSP"]),
        .testTarget(name: "SmixxCoreTests", dependencies: ["SmixxCore", "MixerDSP"])
    ],
    swiftLanguageModes: [.v5]
)
