// swift-tools-version: 5.10
import PackageDescription
import Foundation

// Lens — a precise, repeatable macOS screenshot utility.
//
// Layered like the rest of our menu-bar apps (Clonk, FileMaster):
//   • LensCore — pure capture/compose logic. ScreenCaptureKit, Vision, Core
//                Graphics only. No iUX, no menu-bar plumbing, so it stays
//                testable and the appstage/icon dev tools can link it cheaply.
//   • LensUI   — the menu-bar host, settings popover, selection overlay, the
//                annotation editor, pin windows. Depends on iUX-MacOS so every
//                surface matches our other apps pixel-for-pixel.
//   • Lens     — the executable shell: @main, AppDelegate adaptor, arg routing.

// Tests are kept local-only (Tests/ is gitignored), so include the test target
// only when it's actually present — a fresh clone without it still builds.
let repoRoot = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let cwd = FileManager.default.currentDirectoryPath
let hasCoreTests = FileManager.default.fileExists(
    atPath: repoRoot.appendingPathComponent("Tests/LensCoreTests").path)
    || FileManager.default.fileExists(atPath: cwd + "/Tests/LensCoreTests")

var targets: [Target] = [
    .target(
        name: "LensCore",
        path: "Sources/LensCore",
        linkerSettings: [
            .linkedFramework("ScreenCaptureKit"),
            .linkedFramework("Vision"),
            .linkedFramework("CoreImage"),
            .linkedFramework("UniformTypeIdentifiers"),
        ]
    ),
    .target(
        name: "LensUI",
        dependencies: [
            "LensCore",
            // Shared UX layer — settings popover shell, menu-bar host, overlay
            // windows. Local path so the two packages iterate in lock-step.
            .product(name: "iUX-MacOS", package: "iUX-MacOS"),
        ],
        path: "Sources/LensUI"
    ),
    .executableTarget(
        name: "Lens",
        dependencies: ["LensCore", "LensUI"],
        path: "Sources/Lens"
    ),
]

if hasCoreTests {
    targets.append(
        .testTarget(
            name: "LensCoreTests",
            dependencies: ["LensCore"],
            path: "Tests/LensCoreTests"
        )
    )
}

let package = Package(
    name: "Lens",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "LensCore", targets: ["LensCore"]),
        .library(name: "LensUI", targets: ["LensUI"]),
        .executable(name: "Lens", targets: ["Lens"]),
    ],
    dependencies: [
        // Shared UX layer — settings popover, menu-bar host, overlay windows.
        // Local path so the two packages can iterate in lock-step.
        .package(path: "../iUX-MacOS"),
    ],
    targets: targets
)
