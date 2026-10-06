// swift-tools-version: 6.0
import Foundation
import PackageDescription

var targets: [Target] = [
    // UI-free logic shared by the app and the hook helper.
    .target(name: "NovaKit", path: "Sources/NovaKit"),
    .executableTarget(
        name: "Nova",
        dependencies: ["NovaKit"],
        path: "Sources/Nova",
        resources: [.process("Resources")]
    ),
    // Tiny helper that Claude Code hooks run; forwards events to Nova.
    .executableTarget(name: "NovaHook", dependencies: ["NovaKit"], path: "Sources/NovaHook"),
]

// The test suite isn't published; it's added only when a Tests folder exists.
let tests = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Tests").path
if FileManager.default.fileExists(atPath: tests + "/NovaKitTests") {
    targets += [
        .testTarget(name: "NovaKitTests", dependencies: ["NovaKit"], path: "Tests/NovaKitTests"),
        .testTarget(name: "NovaAppTests", dependencies: ["Nova", "NovaKit"], path: "Tests/NovaAppTests"),
    ]
}

let package = Package(
    name: "Nova",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "Nova", targets: ["Nova"]),
        .executable(name: "nova-hook", targets: ["NovaHook"]),
    ],
    targets: targets
)
