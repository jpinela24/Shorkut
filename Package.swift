// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Shorkut",
    platforms: [.macOS(.v13)],
    targets: [
        // build.sh compiles Sources/Shorkut and Sources/ShorkutCore together
        // into one flat binary with no module boundary (see ShortcutStore.swift's
        // `#if canImport(ShorkutCore)` guard), so this SPM dependency only
        // matters for `swift build`/`swift test`, not the real app build.
        .executableTarget(
            name: "Shorkut",
            dependencies: ["ShorkutCore"],
            path: "Sources/Shorkut"
        ),
        // Pure, UI-free filename/URL sanitization helpers, kept dependency-free
        // (Foundation only) so they're unit-testable without pulling in the
        // rest of the app (AppKit/SwiftUI).
        .target(
            name: "ShorkutCore",
            path: "Sources/ShorkutCore"
        ),
        .testTarget(
            name: "ShorkutCoreTests",
            dependencies: ["ShorkutCore"],
            path: "Tests/ShorkutCoreTests"
        )
    ]
)
