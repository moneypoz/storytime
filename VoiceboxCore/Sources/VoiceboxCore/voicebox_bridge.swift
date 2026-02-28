// voicebox_bridge.swift
//
// Stub implementations matching voicebox.udl (UniFFI interface).
// This file replaces the real UniFFI-generated voicebox_bridge.swift so the
// project compiles without VoiceboxBridge.xcframework (the Rust XCFramework).
//
// All functions throw or return empty data at runtime — replace this file with
// the output of `uniffi-bindgen generate` once scripts/build_xcframework.sh
// has been run on a Mac with the Rust toolchain installed.
//
// ── Swap checklist ────────────────────────────────────────────────────────
//  1. Run scripts/build_xcframework.sh
//  2. Copy generated voicebox_bridge.swift here (overwrite this file)
//  3. Restore binaryTarget + dependency in VoiceboxCore/Package.swift

import Foundation

// MARK: - Namespace functions (voicebox_bridge namespace in UDL)

/// Initialise the shared Tokio runtime. Call once at app launch.
public func setupTokioRuntime() {}

/// Abort any in-progress synthesize call at the next checkpoint.
public func cancelSynthesis() {}

/// Download the model from HuggingFace Hub into cache_dir.
public func downloadModel(cacheDir: String) async throws -> String {
    throw VoiceboxError.initFailed
}

// MARK: - VoiceboxEngine

/// Wraps the Qwen3-TTS inference engine.
public class VoiceboxEngine {

    public init(modelPath: String) throws {
        throw VoiceboxError.initFailed
    }

    /// Synthesise text using the voice profile WAV at profile_path.
    /// Returns 16-bit mono PCM WAV bytes at 24 000 Hz.
    public func synthesize(text: String, profilePath: String) async throws -> [UInt8] {
        throw VoiceboxError.synthesisError
    }

    /// Normalise ref_audio (raw WAV bytes) into a 24 kHz mono voice profile.
    public func createVoiceProfile(refAudio: [UInt8]) async throws -> [UInt8] {
        throw VoiceboxError.profileError
    }
}

// MARK: - VoiceboxError

public enum VoiceboxError: Error, LocalizedError {
    case initFailed
    case synthesisError
    case profileError

    public var errorDescription: String? {
        switch self {
        case .initFailed:     return "VoiceboxEngine failed to initialize."
        case .synthesisError: return "Speech synthesis failed."
        case .profileError:   return "Voice profile creation failed."
        }
    }
}
