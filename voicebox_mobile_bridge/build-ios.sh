#!/usr/bin/env bash
# voicebox_mobile_bridge/build-ios.sh
#
# Compiles the voicebox_mobile_bridge crate for iOS device + simulator,
# generates UniFFI Swift bindings, and packages everything into an XCFramework.
#
# ── Prerequisites (one-time setup on macOS) ───────────────────────────────────
#   xcode-select --install
#   curl https://sh.rustup.rs -sSf | sh
#   rustup target add aarch64-apple-ios aarch64-apple-ios-sim
#   cargo install uniffi-bindgen-cli --version 0.28
#
# ── Usage ─────────────────────────────────────────────────────────────────────
#   cd voicebox_mobile_bridge
#   bash build-ios.sh            # release (default)
#   bash build-ios.sh debug      # debug build — faster compile, larger binary
#
# ── Outputs ───────────────────────────────────────────────────────────────────
#   ../Frameworks/VoiceboxBridge.xcframework   ← drag into Xcode
#   ../VoiceboxCore/Sources/VoiceboxCore/voicebox_bridge.swift  ← UniFFI glue
#
# ── Xcode integration (after running this script) ─────────────────────────────
#   Option A — XCFramework direct link:
#     1. Drag Frameworks/VoiceboxBridge.xcframework into the project navigator
#     2. Target → General → Frameworks, Libraries: add VoiceboxBridge.xcframework
#     3. Copy the generated voicebox_bridge.swift into your app target
#
#   Option B — VoiceboxCore Swift Package (recommended):
#     File → Add Package Dependencies → Add Local → select ../VoiceboxCore
#     The package already references the XCFramework as a binary target.

set -euo pipefail

# ── Paths ─────────────────────────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
CRATE_DIR="$SCRIPT_DIR"

FRAMEWORKS_DIR="$REPO_ROOT/Frameworks"
SWIFT_SOURCES="$REPO_ROOT/VoiceboxCore/Sources/VoiceboxCore"
BINDINGS_DIR="$CRATE_DIR/bindings"
STAGING_DIR="$CRATE_DIR/staging"
LIB_NAME="voicebox_bridge"
XCFW="$FRAMEWORKS_DIR/VoiceboxBridge.xcframework"

# ── Build profile ─────────────────────────────────────────────────────────────

PROFILE="${1:-release}"
if [[ "$PROFILE" == "release" ]]; then
    CARGO_FLAGS="--release"
else
    CARGO_FLAGS=""
fi

# ── Guard: macOS only ─────────────────────────────────────────────────────────

if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "✗  This script must run on macOS (needs Xcode toolchain + Metal SDK)."
    exit 1
fi

# ── Guard: required tools ─────────────────────────────────────────────────────

for tool in cargo rustup uniffi-bindgen xcodebuild; do
    if ! command -v "$tool" &>/dev/null; then
        echo "✗  '$tool' not found."
        [[ "$tool" == "uniffi-bindgen" ]] && \
            echo "   Install: cargo install uniffi-bindgen-cli --version 0.28"
        exit 1
    fi
done

# ── Step 1: Ensure iOS targets are present ────────────────────────────────────

echo "▶  [1/5] Ensuring iOS Rust targets are installed..."
rustup target add aarch64-apple-ios aarch64-apple-ios-sim 2>/dev/null || true

# ── Step 2: Compile for device ────────────────────────────────────────────────

echo "▶  [2/5] Compiling for aarch64-apple-ios ($PROFILE)..."
(cd "$CRATE_DIR" && cargo build $CARGO_FLAGS --target aarch64-apple-ios)

DEVICE_LIB="$CRATE_DIR/target/aarch64-apple-ios/$PROFILE/lib${LIB_NAME}.a"

# ── Step 3: Compile for simulator ─────────────────────────────────────────────

echo "▶  [3/5] Compiling for aarch64-apple-ios-sim ($PROFILE)..."
(cd "$CRATE_DIR" && cargo build $CARGO_FLAGS --target aarch64-apple-ios-sim)

SIM_LIB="$CRATE_DIR/target/aarch64-apple-ios-sim/$PROFILE/lib${LIB_NAME}.a"

# ── Step 4: Generate Swift bindings ───────────────────────────────────────────
#
# Generate from the compiled device library — not from voicebox.udl directly.
# The compiled .a embeds UniFFI metadata (via include_scaffolding!) so bindgen
# produces Swift that exactly matches what was compiled, not just the UDL text.

echo "▶  [4/5] Generating Swift bindings from compiled library..."
rm -rf "$BINDINGS_DIR"
mkdir -p "$BINDINGS_DIR"

uniffi-bindgen generate \
    --library "$DEVICE_LIB" \
    --language swift \
    --out-dir "$BINDINGS_DIR"

# Verify expected outputs exist
for f in "${LIB_NAME}.swift" "${LIB_NAME}FFI.h" "${LIB_NAME}FFI.modulemap"; do
    if [[ ! -f "$BINDINGS_DIR/$f" ]]; then
        echo "✗  uniffi-bindgen did not produce $f — check your UDL and lib.rs."
        exit 1
    fi
done

# Copy the Swift glue to VoiceboxCore (compiled by the Swift Package)
mkdir -p "$SWIFT_SOURCES"
cp "$BINDINGS_DIR/${LIB_NAME}.swift" "$SWIFT_SOURCES/"
echo "   → $SWIFT_SOURCES/${LIB_NAME}.swift"

# ── Step 5: Package XCFramework ───────────────────────────────────────────────
#
# xcodebuild -create-xcframework -library requires each .a to be accompanied
# by a -headers directory.  The directory must contain the C header and a
# modulemap so Clang and Swift can resolve the symbols.

echo "▶  [5/5] Packaging XCFramework..."
rm -rf "$XCFW" "$STAGING_DIR"

for SLICE in device sim; do
    HDR_DIR="$STAGING_DIR/$SLICE/Headers"
    mkdir -p "$HDR_DIR"
    cp "$BINDINGS_DIR/${LIB_NAME}FFI.h"         "$HDR_DIR/"
    cp "$BINDINGS_DIR/${LIB_NAME}FFI.modulemap"  "$HDR_DIR/"
done

mkdir -p "$FRAMEWORKS_DIR"

xcodebuild -create-xcframework \
    -library "$DEVICE_LIB" \
    -headers "$STAGING_DIR/device/Headers" \
    -library "$SIM_LIB" \
    -headers "$STAGING_DIR/sim/Headers" \
    -output "$XCFW"

rm -rf "$STAGING_DIR"

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "✔  XCFramework : $XCFW"
echo "✔  Swift glue  : $SWIFT_SOURCES/${LIB_NAME}.swift"
echo ""
echo "Next steps"
echo "──────────"
echo "  Option A — VoiceboxCore Swift Package (recommended):"
echo "    Xcode → File → Add Package Dependencies → Add Local"
echo "    Select: $REPO_ROOT/VoiceboxCore"
echo ""
echo "  Option B — XCFramework direct:"
echo "    Drag $XCFW into your Xcode project"
echo "    Target → General → Frameworks: add VoiceboxBridge.xcframework"
echo "    Add ${LIB_NAME}.swift to your app target"
echo ""
echo "  Then in StoryTimeApp.init() call:  setupTokioRuntime()"
