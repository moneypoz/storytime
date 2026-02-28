// build.rs — voicebox_mobile_bridge
//
// Generates UniFFI Rust scaffolding from src/voicebox.udl.
// The generated code is spliced into lib.rs via uniffi::include_scaffolding!().
//
// To regenerate Swift bindings after an API change (run on macOS):
//
//   cargo uniffi-bindgen generate \
//     --library target/aarch64-apple-ios/release/libvoicebox_bridge.a \
//     --language swift \
//     --out-dir ../VoiceboxCore/Sources/VoiceboxCore/
//
// The full XCFramework pipeline (compile + bindgen + package) is in
// scripts/build_xcframework.sh.

fn main() {
    uniffi::generate_scaffolding("src/voicebox.udl").unwrap();
}
