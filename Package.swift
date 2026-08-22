// swift-tools-version: 6.0
import Foundation
import PackageDescription

// Command Line Tools ship Testing.framework but hand its directory to the
// compiler as `-I` rather than `-F`, so nothing can import it. This fixes the
// test target; SwiftPM's synthesised runner target is not reachable from a
// manifest, so `swift test` still needs the same `-F` on the command line (see
// docs/SPEC.md § Environment). With Xcode installed neither is necessary.
let toolsFrameworks = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let toolsLibraries = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"
let needsTestingSearchPaths = FileManager.default.fileExists(atPath: toolsFrameworks + "/Testing.framework")
    && !FileManager.default.fileExists(atPath: "/Applications/Xcode.app")

let testSwiftSettings: [SwiftSetting] = needsTestingSearchPaths
    ? [.unsafeFlags(["-F", toolsFrameworks])] : []
let testLinkerSettings: [LinkerSetting] = needsTestingSearchPaths
    ? [.unsafeFlags([
        "-F", toolsFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", toolsFrameworks,
        "-Xlinker", "-rpath", "-Xlinker", toolsLibraries,
    ])] : []

let package = Package(
    name: "yabai-stacks",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "yabai-stacks", targets: ["yabai-stacks"]),
        .library(name: "YabaiStacksCore", targets: ["YabaiStacksCore"]),
        .library(name: "YabaiStacksUI", targets: ["YabaiStacksUI"]),
    ],
    targets: [
        .target(name: "YabaiStacksCore"),
        .target(name: "YabaiStacksUI", dependencies: ["YabaiStacksCore"]),
        .executableTarget(
            name: "yabai-stacks",
            dependencies: ["YabaiStacksCore", "YabaiStacksUI"]
        ),
        .testTarget(
            name: "YabaiStacksCoreTests",
            dependencies: ["YabaiStacksCore"],
            path: "Tests",
            sources: ["YabaiStacksCoreTests"],
            resources: [.copy("Fixtures")],
            swiftSettings: testSwiftSettings,
            linkerSettings: testLinkerSettings
        ),
    ]
)
