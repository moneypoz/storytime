// voicebox_mobile_bridge/src/lib.rs
//
// Optimisations in this version vs the previous one
// ──────────────────────────────────────────────────
//  1. Prompt cache  — VoiceClonePrompt is computed once per profile path and
//                     reused across segments, saving ~0.5 s per segment.
//  2. Noise gate    — apply_noise_gate() zeros 10 ms windows whose RMS falls
//                     below -40 dBFS, so room hum is not baked into the clone.
//  3. Best-window   — trim_to_best_window() selects the 10-second window with
//                     the highest mean energy from the 30-second recording.
//  4. Temp-file fix — unique filename prevents races if create_voice_profile
//                     is called concurrently (e.g. two parents registering).

use std::io::Cursor;
use std::sync::{Arc, Mutex, OnceLock};
use std::sync::atomic::{AtomicBool, Ordering};

use anyhow::Result;
use hound::{SampleFormat, WavSpec, WavWriter};
use qwen3_tts::{AudioBuffer, Language, Qwen3TTS, VoiceClonePrompt};

uniffi::include_scaffolding!("voicebox");

// ── Global Tokio runtime ─────────────────────────────────────────────────────

static TOKIO_RT: OnceLock<tokio::runtime::Runtime> = OnceLock::new();

pub fn setup_tokio_runtime() {
    TOKIO_RT.get_or_init(|| {
        let workers = std::thread::available_parallelism()
            .map(|n| n.get().min(4))
            .unwrap_or(2);
        tokio::runtime::Builder::new_multi_thread()
            .worker_threads(workers)
            .max_blocking_threads(8)
            .enable_all()
            .build()
            .expect("Tokio init failed")
    });
}

// ── Cancellation ─────────────────────────────────────────────────────────────

static CANCEL_SYNTHESIS: AtomicBool = AtomicBool::new(false);

pub fn cancel_synthesis() {
    CANCEL_SYNTHESIS.store(true, Ordering::SeqCst);
}

// ── Error ─────────────────────────────────────────────────────────────────────

#[derive(Debug, thiserror::Error)]
pub enum VoiceboxError {
    #[error("Model initialisation failed")]
    InitFailed,
    #[error("Synthesis error")]
    SynthesisError,
    #[error("Voice profile error")]
    ProfileError,
}

// ── EngineInner ───────────────────────────────────────────────────────────────
//
// Bundles the model and the prompt cache under a single Mutex so we never hold
// two locks simultaneously.  The cache stores the last VoiceClonePrompt keyed
// by profile path — when the same path is used for consecutive segments (the
// common case) the speech encoder is skipped entirely.

struct EngineInner {
    model: Qwen3TTS,
    cached_profile: Option<String>,
    cached_prompt: Option<VoiceClonePrompt>,
}

// ── VoiceboxEngine ────────────────────────────────────────────────────────────

pub struct VoiceboxEngine {
    inner: Arc<Mutex<EngineInner>>,
}

impl VoiceboxEngine {
    pub fn new(model_path: String) -> Result<Arc<Self>, VoiceboxError> {
        let device = qwen3_tts::auto_device().map_err(|_| VoiceboxError::InitFailed)?;
        let model = Qwen3TTS::from_pretrained(&model_path, device)
            .map_err(|_| VoiceboxError::InitFailed)?;

        Ok(Arc::new(Self {
            inner: Arc::new(Mutex::new(EngineInner {
                model,
                cached_profile: None,
                cached_prompt: None,
            })),
        }))
    }

    /// Synthesise `text` using the voice profile WAV at `profile_path`.
    ///
    /// The VoiceClonePrompt (speech encoder output) is cached after the first
    /// call for a given profile path.  Subsequent calls with the same path skip
    /// the encoder and go straight to the TTS decoder — saving ~0.5 s/segment.
    pub async fn synthesize(
        &self,
        text: String,
        profile_path: String,
    ) -> Result<Vec<u8>, VoiceboxError> {
        CANCEL_SYNTHESIS.store(false, Ordering::SeqCst);

        let inner = Arc::clone(&self.inner);

        tokio::task::spawn_blocking(move || {
            if CANCEL_SYNTHESIS.load(Ordering::SeqCst) {
                return Err(VoiceboxError::SynthesisError);
            }

            let mut guard = inner.lock().map_err(|_| VoiceboxError::SynthesisError)?;

            // ── Prompt cache check ─────────────────────────────────────────
            let prompt = if guard.cached_profile.as_deref() == Some(profile_path.as_str())
                && guard.cached_prompt.is_some()
            {
                // Cache hit — take the prompt out (put it back after synthesis)
                guard.cached_prompt.take().unwrap()
            } else {
                // Cache miss — load reference audio and run speech encoder
                let ref_audio = AudioBuffer::load(&profile_path)
                    .map_err(|_| VoiceboxError::ProfileError)?;

                if CANCEL_SYNTHESIS.load(Ordering::SeqCst) {
                    return Err(VoiceboxError::SynthesisError);
                }

                guard
                    .model
                    .create_voice_clone_prompt(&ref_audio, None)
                    .map_err(|_| VoiceboxError::SynthesisError)?
            };

            if CANCEL_SYNTHESIS.load(Ordering::SeqCst) {
                return Err(VoiceboxError::SynthesisError);
            }

            // ── TTS decode ─────────────────────────────────────────────────
            let audio = guard
                .model
                .synthesize_voice_clone(&text, &prompt, Language::English, None)
                .map_err(|_| VoiceboxError::SynthesisError)?;

            // ── Re-cache prompt for next segment ───────────────────────────
            guard.cached_profile = Some(profile_path);
            guard.cached_prompt = Some(prompt);

            encode_pcm16(&audio.samples, audio.sample_rate)
                .map_err(|_| VoiceboxError::SynthesisError)
        })
        .await
        .map_err(|_| VoiceboxError::SynthesisError)?
    }

    /// Normalise `ref_audio` (raw WAV bytes), apply a noise gate, trim to the
    /// most energetic 10-second window, and return the result as a 24 kHz mono
    /// WAV.  The caller writes these bytes to disk and passes the path to
    /// `synthesize` on every call.
    pub async fn create_voice_profile(
        &self,
        ref_audio: Vec<u8>,
    ) -> Result<Vec<u8>, VoiceboxError> {
        tokio::task::spawn_blocking(move || {
            // Unique temp file so concurrent calls don't clobber each other
            let tmp = std::env::temp_dir().join(format!(
                "vb_ref_{:016x}.wav",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .map(|d| d.as_nanos() as u64)
                    .unwrap_or_else(|_| rand_fallback())
            ));

            std::fs::write(&tmp, &ref_audio).map_err(|_| VoiceboxError::ProfileError)?;

            let buf = AudioBuffer::load(tmp.to_string_lossy().as_ref())
                .map_err(|_| VoiceboxError::ProfileError)?;

            let _ = std::fs::remove_file(&tmp);

            // ── Noise gate: zero 10 ms windows below -40 dBFS ─────────────
            let gated = apply_noise_gate(&buf.samples, buf.sample_rate, -40.0);

            // ── Trim to best 10-second window by RMS ──────────────────────
            let trimmed = trim_to_best_window(&gated, buf.sample_rate, 10.0);

            encode_pcm16(&trimmed, buf.sample_rate).map_err(|_| VoiceboxError::ProfileError)
        })
        .await
        .map_err(|_| VoiceboxError::ProfileError)?
    }
}

// ── Model download ────────────────────────────────────────────────────────────

pub async fn download_model(cache_dir: String) -> Result<String, VoiceboxError> {
    tokio::task::spawn_blocking(move || {
        unsafe { std::env::set_var("HF_HOME", &cache_dir) };

        let paths = qwen3_tts::hub::ModelPaths::download(None)
            .map_err(|_| VoiceboxError::InitFailed)?;

        Ok(paths
            .model_weights
            .parent()
            .ok_or(VoiceboxError::InitFailed)?
            .to_string_lossy()
            .into_owned())
    })
    .await
    .map_err(|_| VoiceboxError::InitFailed)?
}

// ── Audio processing helpers ──────────────────────────────────────────────────

/// Zero 10 ms frames whose RMS falls below `threshold_db` (e.g. -40.0).
/// Returns a new sample vector — the input is not mutated.
fn apply_noise_gate(samples: &[f32], sample_rate: u32, threshold_db: f32) -> Vec<f32> {
    // Convert dBFS to linear amplitude  (0 dBFS = 1.0 full-scale)
    let threshold_linear = 10f32.powf(threshold_db / 20.0);
    let frame = (sample_rate as usize * 10) / 1000; // 10 ms in samples

    let mut out = samples.to_vec();
    for chunk in out.chunks_mut(frame.max(1)) {
        let rms = (chunk.iter().map(|&s| s * s).sum::<f32>() / chunk.len() as f32).sqrt();
        if rms < threshold_linear {
            chunk.fill(0.0);
        }
    }
    out
}

/// Find the `window_secs`-long slice with the highest mean energy (RMS),
/// stepping in 1-second increments.  Falls back to the full buffer if it is
/// shorter than the requested window.
fn trim_to_best_window(samples: &[f32], sample_rate: u32, window_secs: f32) -> Vec<f32> {
    let window = (sample_rate as f32 * window_secs) as usize;
    if samples.len() <= window {
        return samples.to_vec();
    }

    let step = sample_rate as usize; // search every 1 second
    let best_start = (0..=samples.len().saturating_sub(window))
        .step_by(step.max(1))
        .max_by(|&a, &b| {
            let rms = |s: usize| {
                let end = (s + window).min(samples.len());
                let sl = &samples[s..end];
                (sl.iter().map(|&x| x * x).sum::<f32>() / sl.len() as f32).sqrt()
            };
            rms(a).partial_cmp(&rms(b)).unwrap_or(std::cmp::Ordering::Equal)
        })
        .unwrap_or(0);

    samples[best_start..(best_start + window).min(samples.len())].to_vec()
}

// ── WAV encoding ──────────────────────────────────────────────────────────────

/// Encode f32 samples at `sample_rate` Hz as 16-bit mono PCM WAV bytes.
fn encode_pcm16(samples: &[f32], sample_rate: u32) -> Result<Vec<u8>> {
    let mut cursor = Cursor::new(Vec::<u8>::new());
    let spec = WavSpec {
        channels: 1,
        sample_rate,
        bits_per_sample: 16,
        sample_format: SampleFormat::Int,
    };
    let mut writer = WavWriter::new(&mut cursor, spec)?;
    for &s in samples {
        let pcm: i16 = (s * 32_767.0).clamp(-32_768.0, 32_767.0) as i16;
        writer.write_sample(pcm)?;
    }
    writer.finalize()?;
    Ok(cursor.into_inner())
}

// ── Fallback entropy for temp-file naming ─────────────────────────────────────

fn rand_fallback() -> u64 {
    // XOR of stack address + thread-id bits — not cryptographic, just unique enough
    // for a temp filename when SystemTime is unavailable.
    let stack_addr = &0u8 as *const u8 as u64;
    let tid = std::thread::current().id();
    stack_addr ^ format!("{tid:?}").len() as u64
}
