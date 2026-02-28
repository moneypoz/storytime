#!/usr/bin/env bash
# scripts/build_xcframework.sh
#
# Builds the voicebox_mobile_bridge Rust crate into an XCFramework and
# generates the UniFFI Swift bindings that go into VoiceboxCore.
#
# Prerequisites (all macOS only):
#   brew install rustup
#   rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#   cargo install uniffi-bindgen   # or: cargo binstall uniffi-bindgen
#
# Usage:
#   bash scripts/build_xcframework.sh           # release build (default)
#   bash scripts/build_xcframework.sh --debug   # debug build (faster compile)
#
# Outputs:
#   Frameworks/VoiceboxBridge.xcframework       (linked by VoiceboxCore Package)
#   VoiceboxCore/Sources/VoiceboxCore/voicebox_bridge.swift   (generated)
#   VoiceboxCore/Sources/VoiceboxCore/voicebox_bridgeFFI.h    (generated)
#   VoiceboxCore/Sources/VoiceboxCore/voicebox_bridgeFFI.modulemap (generated)

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────

CRATE_DIR="$(cd "$(dirname "$0")/../voicebox_mobile_bridge" && pwd)"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SWIFT_SOURCES="${REPO_ROOT}/VoiceboxCore/Sources/VoiceboxCore"
FRAMEWORKS_DIR="${REPO_ROOT}/Frameworks"
XCFRAMEWORK="${FRAMEWORKS_DIR}/VoiceboxBridge.xcframework"
LIB_NAME="voicebox_bridge"

PROFILE="release"
CARGO_FLAGS="--release"
if [[ "${1:-}" == "--debug" ]]; then
    PROFILE="debug"
    CARGO_FLAGS=""
fi

# ── Step 1: Compile for device (aarch64-apple-ios) ───────────────────────────

echo "▶ Compiling for aarch64-apple-ios (${PROFILE})…"
(cd "${CRATE_DIR}" && cargo build ${CARGO_FLAGS} --target aarch64-apple-ios)

DEVICE_LIB="${CRATE_DIR}/target/aarch64-apple-ios/${PROFILE}/lib${LIB_NAME}.a"

# ── Step 2: Compile for simulator (aarch64-apple-ios-sim) ────────────────────

echo "▶ Compiling for aarch64-apple-ios-sim (${PROFILE})…"
(cd "${CRATE_DIR}" && cargo build ${CARGO_FLAGS} --target aarch64-apple-ios-sim)

SIM_LIB="${CRATE_DIR}/target/aarch64-apple-ios-sim/${PROFILE}/lib${LIB_NAME}.a"

# ── Step 3: Generate Swift bindings via uniffi-bindgen ───────────────────────

echo "▶ Generating UniFFI Swift bindings…"
BINDINGS_DIR="${CRATE_DIR}/bindings"
mkdir -p "${BINDINGS_DIR}"

(cd "${CRATE_DIR}" && cargo run --bin uniffi-bindgen -- generate \
    --library "${DEVICE_LIB}" \
    --language swift \
    --out-dir "${BINDINGS_DIR}")

echo "  → Bindings written to ${BINDINGS_DIR}"

# Copy Swift source to VoiceboxCore (replaces the stub voicebox_bridge.swift)
mkdir -p "${SWIFT_SOURCES}"
cp "${BINDINGS_DIR}"/*.swift "${SWIFT_SOURCES}/"
echo "  → Swift source copied to ${SWIFT_SOURCES}"

# ── Step 4: Package into XCFramework ─────────────────────────────────────────
# Use -library + -headers (simpler than wrapping in .framework directories).

echo "▶ Packaging XCFramework…"
rm -rf "${XCFRAMEWORK}"
mkdir -p "${FRAMEWORKS_DIR}"

xcodebuild -create-xcframework \
    -library "${DEVICE_LIB}"  -headers "${BINDINGS_DIR}" \
    -library "${SIM_LIB}"     -headers "${BINDINGS_DIR}" \
    -output "${XCFRAMEWORK}"

echo "✔ XCFramework written to ${XCFRAMEWORK}"

# ── Step 5: Update Package.swift checksum (if swiftpm checksum differs) ──────

echo ""
echo "Done. Next steps:"
echo "  1. Delete VoiceboxCore/Sources/VoiceboxCore/voicebox_bridge.swift (the stub)"
echo "  2. Restore the binaryTarget in VoiceboxCore/Package.swift (see swap checklist"
echo "     at the top of voicebox_bridge.swift) — relativePath = Frameworks/VoiceboxBridge.xcframework"
echo "  3. Build the storytime Xcode project — VoiceboxCore should resolve."
echo ""
