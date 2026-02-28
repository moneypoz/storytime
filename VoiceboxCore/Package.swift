// swift-tools-version: 5.9
// VoiceboxCore/Package.swift
//
// Swift Package that wraps the VoiceboxBridge XCFramework (built from the
// voicebox_mobile_bridge Rust crate via scripts/build_xcframework.sh).
//
// Consumers (the storytime Xcode target) add this package via:
//   File → Add Package Dependencies → Add Local → select this directory
//
// ── Stub mode (current) ───────────────────────────────────────────────────
// voicebox_bridge.swift provides pure-Swift stubs so the project compiles
// without the Rust XCFramework.  When VoiceboxBridge.xcframework is ready:
//   1. Run scripts/build_xcframework.sh
//   2. Delete Sources/VoiceboxCore/voicebox_bridge.swift
//   3. Restore the binaryTarget block and .target dependency below
//   4. Copy the UniFFI-generated voicebox_bridge.swift into Sources/VoiceboxCore/

import PackageDescription

let package = Package(
    name: "VoiceboxCore",
    platforms: [.iOS(.v17)],
    products: [
        .library(
            name: "VoiceboxCore",
            targets: ["VoiceboxCore"]
        )
    ],
    targets: [
        // ── Swift sources ──────────────────────────────────────────────────
        // Hand-written Swift wrapper (VoiceboxCore.swift + ModelManager.swift)
        // plus voicebox_bridge.swift (stub — replace with UniFFI-generated
        // file once scripts/build_xcframework.sh has been run).
        .target(
            name: "VoiceboxCore",
            dependencies: [],
            path: "Sources/VoiceboxCore"
        )
    ]
)
