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
mkdir -p "${SWIFT_SOURCES}"

cargo uniffi-bindgen generate \
    --library "${DEVICE_LIB}" \
    --language swift \
    --out-dir "${SWIFT_SOURCES}"

echo "  → Swift sources written to ${SWIFT_SOURCES}"

# ── Step 4: Package into XCFramework ─────────────────────────────────────────

echo "▶ Packaging XCFramework…"
rm -rf "${XCFRAMEWORK}"
mkdir -p "${FRAMEWORKS_DIR}"

# Wrap each .a in a minimal .framework directory — xcodebuild -create-xcframework
# requires frameworks or libraries with headers, not raw .a files.

make_framework() {
    local lib="$1"
    local platform="$2"   # iphoneos | iphonesimulator
    local out_dir="${FRAMEWORKS_DIR}/staging/${platform}"
    local fw_dir="${out_dir}/${LIB_NAME}.framework"

    rm -rf "${fw_dir}"
    mkdir -p "${fw_dir}/Headers"

    # Copy the static lib as the framework binary (no extension)
    cp "${lib}" "${fw_dir}/${LIB_NAME}"

    # Copy the generated C header
    cp "${SWIFT_SOURCES}/${LIB_NAME}FFI.h" "${fw_dir}/Headers/"

    # Minimal Info.plist
    cat > "${fw_dir}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>  <string>${LIB_NAME}</string>
    <key>CFBundleIdentifier</key>  <string>com.storytime.${LIB_NAME}</string>
    <key>CFBundlePackageType</key> <string>FMWK</string>
    <key>MinimumOSVersion</key>    <string>17.0</string>
</dict>
</plist>
PLIST

    echo "${fw_dir}"
}

DEVICE_FW=$(make_framework "${DEVICE_LIB}" "iphoneos")
SIM_FW=$(make_framework "${SIM_LIB}" "iphonesimulator")

xcodebuild -create-xcframework \
    -framework "${DEVICE_FW}" \
    -framework "${SIM_FW}" \
    -output "${XCFRAMEWORK}"

rm -rf "${FRAMEWORKS_DIR}/staging"

echo "✔ XCFramework written to ${XCFRAMEWORK}"

# ── Step 5: Update Package.swift checksum (if swiftpm checksum differs) ──────

echo ""
echo "Done. Next steps:"
echo "  1. Open VoiceboxCore/Package.swift"
echo "  2. Update the 'checksum' field with the output of:"
echo "     swift package compute-checksum ${XCFRAMEWORK}"
echo "  3. Build the storytime Xcode project — VoiceboxCore should resolve."
echo ""
