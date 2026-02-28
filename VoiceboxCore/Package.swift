// swift-tools-version: 5.9
// VoiceboxCore/Package.swift
//
// Swift Package that wraps the VoiceboxBridge XCFramework (built from the
// voicebox_mobile_bridge Rust crate via scripts/build_xcframework.sh).
//
// Consumers (the storytime Xcode target) add this package via:
//   File → Add Package Dependencies → Add Local → select this directory
//
// The XCFramework is referenced as a binaryTarget so no Rust toolchain is
// required on the build machine after the .xcframework has been generated.
//
// ── Checksum ──────────────────────────────────────────────────────────────
// After running scripts/build_xcframework.sh, update the `checksum` field:
//
//   swift package compute-checksum ../Frameworks/VoiceboxBridge.xcframework
//
// Replace the placeholder below with the resulting hex string.

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
        // ── Binary target ──────────────────────────────────────────────────
        // References the XCFramework produced by scripts/build_xcframework.sh.
        // `path` is relative to this Package.swift — ../Frameworks/ sits at
        // the repo root alongside voicebox_mobile_bridge and VoiceboxCore.
        .binaryTarget(
            name: "VoiceboxBridge",
            path: "../Frameworks/VoiceboxBridge.xcframework"
        ),

        // ── Swift sources ──────────────────────────────────────────────────
        // Hand-written Swift wrapper (VoiceboxCore.swift + ModelManager.swift)
        // plus the three UniFFI-generated files copied here by the build script:
        //   voicebox_bridge.swift
        //   voicebox_bridgeFFI.h        (in publicHeadersPath)
        //   voicebox_bridgeFFI.modulemap
        .target(
            name: "VoiceboxCore",
            dependencies: ["VoiceboxBridge"],
            path: "Sources/VoiceboxCore",
            publicHeadersPath: "."
        )
    ]
)
