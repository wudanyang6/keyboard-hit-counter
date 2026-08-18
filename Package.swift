// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "KeyboardHitCounter",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "CAtomic"),
        .target(
            name: "KeyboardHitCounterCore",
            dependencies: ["CAtomic"]
        ),
        .executableTarget(
            name: "KeyboardHitCounter",
            dependencies: ["KeyboardHitCounterCore"]
        ),
        .testTarget(
            name: "KeyboardHitCounterCoreTests",
            dependencies: ["KeyboardHitCounterCore", "CAtomic"]
        ),
    ]
)