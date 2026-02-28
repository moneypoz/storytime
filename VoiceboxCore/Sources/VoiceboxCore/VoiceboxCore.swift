// VoiceboxCore/Sources/VoiceboxCore/VoiceboxCore.swift
//
// Optimisations in this version
// ──────────────────────────────
//  5. hasVoiceProfile  — public Bool so TTSPlayer can gate the Voicebox path.
//  6. Disk WAV cache   — synthesized audio keyed by SHA-256(profilePath+text)
//                        persisted in Library/Caches/VoiceboxAudio/.
//                        Replay of a story is instant after the first listen.
//  7. Sentence chunks  — texts longer than 80 words are split at sentence
//                        boundaries, each chunk synthesized separately, then
//                        the PCM streams are stitched into one WAV.
//  8. load() is async  — model init (~1-3 s) runs on a background thread so
//                        the main actor is never blocked.

import AVFoundation
import CryptoKit
import Foundation

// MARK: - VoiceboxService

@MainActor
public final class VoiceboxService: ObservableObject {

    public static let shared = VoiceboxService()

    // MARK: - Published

    @Published public private(set) var isLoaded = false
    @Published public private(set) var isSynthesising = false
    @Published public private(set) var lastError: String?

    /// True once a voice profile path has been registered via setVoiceProfile().
    public var hasVoiceProfile: Bool { voiceProfilePath != nil }

    // MARK: - Private

    private var engine: VoiceboxEngine?
    private var audioPlayer: AVAudioPlayer?
    private var voiceProfilePath: String?

    private init() {}

    // MARK: - Lifecycle

    /// Load the Qwen3-TTS engine from `modelPath`.
    ///
    /// The blocking model-init (~1-3 s) runs on a detached background task so
    /// the main actor is never stalled.  Safe to call from any context.
    public func load(modelPath: String) async throws {
        let loaded = try await Task.detached(priority: .background) {
            try VoiceboxEngine(modelPath: modelPath)
        }.value
        self.engine = loaded
        self.isLoaded = true
    }

    /// Register the voice profile WAV that `synthesize` will use.
    public func setVoiceProfile(path: String) {
        voiceProfilePath = path
    }

    // MARK: - Voice cloning

    /// Normalise raw recording bytes, apply noise gate + best-window trim (in
    /// Rust), write the result to `outputPath`, and register it as the active
    /// voice profile.
    public func createVoiceProfile(audioData: Data, outputPath: String) async throws {
        guard let engine else { throw VoiceCoreError.notLoaded }
        let normalized = try await engine.createVoiceProfile(refAudio: Array(audioData))
        try Data(normalized).write(to: URL(fileURLWithPath: outputPath))
        voiceProfilePath = outputPath
    }

    // MARK: - Synthesis

    /// Synthesise `text` using the registered voice profile.
    ///
    /// - Checks the disk cache first — if a WAV exists for this text+profile
    ///   pair the Rust engine is not called at all.
    /// - Splits text at sentence boundaries when it exceeds 80 words, then
    ///   stitches the resulting WAV chunks into one continuous stream.
    /// - Returns 16-bit mono PCM WAV bytes at 24 000 Hz.
    public func synthesize(_ text: String) async throws -> Data {
        guard let engine else { throw VoiceCoreError.notLoaded }
        guard let profilePath = voiceProfilePath else { throw VoiceCoreError.noVoiceProfile }

        isSynthesising = true
        defer { isSynthesising = false }

        let key = cacheKey(text: text, profilePath: profilePath)
        if let cached = readCache(key: key) { return cached }

        do {
            let chunks = sentenceChunks(from: text)
            let wavs: [Data]

            if chunks.count == 1 {
                let bytes = try await engine.synthesize(text: text, profilePath: profilePath)
                wavs = [Data(bytes)]
            } else {
                var parts: [Data] = []
                for chunk in chunks {
                    let bytes = try await engine.synthesize(text: chunk, profilePath: profilePath)
                    parts.append(Data(bytes))
                }
                wavs = parts
            }

            let result = wavs.count == 1 ? wavs[0] : stitchWAVs(wavs)
            writeCache(result, key: key)
            return result

        } catch let e as VoiceboxError {
            throw VoiceCoreError.bridge(e)
        }
    }

    // MARK: - Playback helpers

    @discardableResult
    public func play(wav: Data) throws -> AVAudioPlayer {
        let player = try AVAudioPlayer(data: wav)
        player.prepareToPlay()
        player.play()
        audioPlayer = player
        return player
    }

    public func stop() {
        audioPlayer?.stop()
        audioPlayer = nil
        cancelSynthesis()
    }

    /// Remove all cached synthesized audio (e.g. after a voice re-clone).
    public func clearAudioCache() {
        try? FileManager.default.removeItem(at: audioCacheDirectory)
    }
}

// MARK: - Sentence chunking

private extension VoiceboxService {

    /// Split `text` at sentence-ending punctuation, grouping into chunks of at
    /// most `maxWords` words.  Returns `[text]` unchanged when text is short.
    func sentenceChunks(from text: String, maxWords: Int = 80) -> [String] {
        let words = text.split(separator: " ").count
        guard words > maxWords else { return [text] }

        // Tokenise into sentences by splitting on ". " / "! " / "? "
        var sentences: [String] = []
        var remainder = text
        let terminators = CharacterSet(charactersIn: ".!?")

        while !remainder.isEmpty {
            if let range = remainder.rangeOfCharacter(from: terminators) {
                let sentence = String(remainder[...range.lowerBound])
                sentences.append(sentence.trimmingCharacters(in: .whitespaces))
                let after = remainder.index(after: range.lowerBound)
                remainder = String(remainder[after...]).trimmingCharacters(in: .whitespaces)
            } else {
                sentences.append(remainder)
                break
            }
        }

        // Greedily group sentences into maxWords-word chunks
        var chunks: [String] = []
        var current = ""
        var currentWords = 0

        for sentence in sentences where !sentence.isEmpty {
            let count = sentence.split(separator: " ").count
            if currentWords + count > maxWords, !current.isEmpty {
                chunks.append(current.trimmingCharacters(in: .whitespaces))
                current = sentence + " "
                currentWords = count
            } else {
                current += sentence + " "
                currentWords += count
            }
        }

        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            chunks.append(current.trimmingCharacters(in: .whitespaces))
        }

        return chunks.isEmpty ? [text] : chunks
    }
}

// MARK: - WAV stitching

private extension VoiceboxService {

    /// Concatenate PCM streams from multiple WAV blobs into one WAV.
    ///
    /// All input WAVs must share the same format (16-bit, mono, 24 kHz) —
    /// which is guaranteed since they all come from `encode_pcm16` in Rust.
    /// The standard PCM WAV header is exactly 44 bytes; we reuse the first
    /// header and patch the size fields to match the combined payload.
    func stitchWAVs(_ wavs: [Data]) -> Data {
        guard wavs.count > 1 else { return wavs.first ?? Data() }

        let headerSize = 44
        var header = Data(wavs[0].prefix(headerSize))
        let allPCM = wavs.reduce(Data()) { $0 + $1.dropFirst(headerSize) }

        func le32(_ v: UInt32) -> [UInt8] {
            let x = v.littleEndian
            return [
                UInt8(x & 0xFF), UInt8((x >> 8) & 0xFF),
                UInt8((x >> 16) & 0xFF), UInt8((x >> 24) & 0xFF)
            ]
        }

        let dataSize = UInt32(allPCM.count)
        let riffSize = UInt32(36 + allPCM.count)
        header.replaceSubrange(4..<8, with: le32(riffSize))
        header.replaceSubrange(40..<44, with: le32(dataSize))
        return header + allPCM
    }
}

// MARK: - Disk WAV cache

private extension VoiceboxService {

    var audioCacheDirectory: URL {
        FileManager.default
            .urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("VoiceboxAudio", isDirectory: true)
    }

    func cacheKey(text: String, profilePath: String) -> String {
        let input = Data("\(profilePath):\(text)".utf8)
        return SHA256.hash(data: input)
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }

    func readCache(key: String) -> Data? {
        let url = audioCacheDirectory.appendingPathComponent("\(key).wav")
        return try? Data(contentsOf: url)
    }

    func writeCache(_ data: Data, key: String) {
        let dir = audioCacheDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? data.write(
            to: dir.appendingPathComponent("\(key).wav"),
            options: .atomic
        )
    }
}

// MARK: - VoiceCoreError

public enum VoiceCoreError: LocalizedError {
    case notLoaded
    case noVoiceProfile
    case bridge(VoiceboxError)

    public var errorDescription: String? {
        switch self {
        case .notLoaded:      return "VoiceboxEngine not loaded — call load(modelPath:) first."
        case .noVoiceProfile: return "No voice profile — record a voice before synthesising."
        case .bridge(let e):  return e.localizedDescription
        }
    }
}
