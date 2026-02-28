// src/bin/uniffi-bindgen.rs
//
// Thin entrypoint so `cargo run --bin uniffi-bindgen` works without a
// separately installed tool.  uniffi re-exports uniffi_bindgen_main()
// when the "cli" feature is enabled.
fn main() {
    uniffi::uniffi_bindgen_main()
}
