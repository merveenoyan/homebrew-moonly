import Foundation
import Combine
import LlamaKit

/// Runs Gemma 4 E4B (QAT) **in-process** via LlamaKit (a Swift wrapper around
/// llama.cpp), instead of shelling out to a separate `llama-server` binary.
///
/// The GGUF is downloaded from the Hugging Face Hub on first use (LlamaKit's
/// `Hub` trait) into the app-owned cache under Application Support, then loaded
/// straight from disk on subsequent runs. Generation is fully local — the only
/// network egress is the one-time, inbound model download from Hugging Face.
///
/// The public surface (``status``, ``detail``, ``ensureRunning()``, ``stop()``,
/// ``chat(system:user:temperature:maxTokens:)``) is unchanged from the previous
/// process-based implementation, so callers don't need to know the engine moved
/// in-process. ``stop()`` releases the model + session to free memory, matching
/// the old "shut the server down after each inference" behavior.
@MainActor
final class LlamaServer: ObservableObject {
    static let shared = LlamaServer()

    /// The single source of model truth — the Hugging Face repo we pull from.
    static let modelRepo = "google/gemma-4-E4B-it-qat-q4_0-gguf"

    /// Glob matching the main weights inside the repo (e.g.
    /// `gemma-4-E4B_q4_0-it.gguf`). The `q4_0` filter keeps us off the optional
    /// multimodal `*-mmproj.gguf` projector (text-only here). Matched with
    /// `LIKE[c]`, so the wildcards must straddle the `q4_0` token in the middle.
    static let modelFilePattern = "*q4_0*.gguf"

    /// Session context window (and single-batch capacity). Sized for the longest
    /// prompt — phase inference with several cycles of daily logs — plus output.
    static let contextTokens: UInt32 = 8192

    enum Status: Equatable {
        case idle            // not loaded yet
        case starting        // loading / downloading on first run
        case ready
        case generating
        case failed(String)

        var isUsable: Bool {
            switch self { case .ready, .generating: return true; default: return false }
        }
    }

    @Published private(set) var status: Status = .idle
    /// Human-readable sub-state (e.g. "Downloading model…"), surfaced in the UI.
    @Published private(set) var detail: String?

    private var model: LlamaModel?
    private var session: LlamaSession?

    private init() {
        // Point swift-huggingface at our app-owned cache so the GGUF lives
        // somewhere predictable and `brew uninstall` (zap) can wipe it. Must be
        // set before the first Hub download.
        try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)
        setenv("HF_HUB_CACHE", Self.cacheDir.path, 1)
    }

    // MARK: - Filesystem locations

    /// App-owned model cache (Python-compatible HF layout: blobs/snapshots/refs).
    static var cacheDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonly/models", isDirectory: true)
    }

    /// Best-effort check for whether the weights have been downloaded yet, so the
    /// UI can warn that first launch will pull ~5 GB. Walks the cache for a
    /// non-`mmproj` `.gguf`.
    var modelLikelyCached: Bool {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: Self.cacheDir,
                                         includingPropertiesForKeys: nil,
                                         options: [.skipsHiddenFiles]) else { return false }
        for case let url as URL in walker where url.pathExtension == "gguf" {
            if !url.lastPathComponent.localizedCaseInsensitiveContains("mmproj") { return true }
        }
        return false
    }

    // MARK: - Lifecycle

    /// Idempotently load the model + session. Safe to call repeatedly.
    func ensureRunning() async {
        switch status {
        case .ready, .generating, .starting: return
        default: break
        }

        // Decide the verb once, up front. When the weights are already cached,
        // swift-huggingface still fires progress callbacks (its first tick is at
        // 0%) while it verifies the snapshot — so keying the message off the
        // progress fraction would briefly flash a misleading "Downloading…".
        // A cached run is really just loading, so we say so and ignore the ticks.
        let alreadyCached = modelLikelyCached
        status = .starting
        detail = alreadyCached ? "Loading model…" : "Downloading model (~5 GB, first run only)…"

        do {
            // `from` downloads (if needed) and loads the GGUF off the main actor.
            // `gpuLayerCount: -1` offloads all layers to Metal on Apple Silicon.
            let loaded = try await LlamaModel.from(
                repo: Self.modelRepo,
                filename: Self.modelFilePattern,
                parameters: LlamaModel.Parameters(gpuLayerCount: -1),
                progress: { [weak self] progress in
                    Task { @MainActor in
                        guard let self, self.status == .starting else { return }
                        guard !alreadyCached else { self.detail = "Loading model…"; return }
                        if progress.fractionCompleted < 1.0 {
                            let pct = Int(progress.fractionCompleted * 100)
                            self.detail = "Downloading model… \(pct)% (first run only)"
                        } else {
                            self.detail = "Loading model…"
                        }
                    }
                }
            )

            detail = "Loading model…"
            // Build the session off the main actor — context allocation is heavy.
            // 8192 gives headroom for the heaviest prompt: phase inference embeds
            // up to 3 full cycles of per-day logs (the old `-c 4096` was already
            // ~70% full on a busy month). batchSize must track contextLength since
            // LlamaKit decodes the whole prompt in a single batch.
            let params = LlamaSession.Parameters(
                contextLength: Self.contextTokens,
                batchSize: Self.contextTokens,
                physicalBatchSize: 512
            )
            let createdSession = try await Task.detached(priority: .userInitiated) {
                try LlamaSession(model: loaded, parameters: params)
            }.value

            model = loaded
            session = createdSession
            status = .ready
            detail = nil
        } catch {
            model = nil
            session = nil
            status = .failed("Couldn't load the model: \(error.localizedDescription)")
            detail = nil
        }
    }

    /// Release the model + session to free memory (Metal buffers + KV cache).
    func stop() {
        session = nil
        model = nil
        status = .idle
        detail = nil
    }

    // MARK: - Chat

    struct ChatMessage: Codable { let role: String; let content: String }

    /// Send a chat completion request and return the assistant's text.
    func chat(system: String, user: String,
              temperature: Double = 0.7, maxTokens: Int = 400) async throws -> String {
        if !status.isUsable { await ensureRunning() }
        guard status.isUsable, let model, let session else { throw LlamaError.notReady(status) }

        status = .generating
        defer { if status == .generating { status = .ready } }

        _ = model // weights are held via `session`; prompt formatting is manual
        let prompt = Self.renderPrompt(system: system, user: user)

        // Mirror the previous sampling config: temperature with top_k 64 / top_p
        // 0.95. Temperature 0 means deterministic greedy decoding.
        let sampler: Sampler = temperature <= 0
            ? .greedy
            : .temperature(Float(temperature), topK: 64, topP: 0.95)

        let text = try await session.complete(
            prompt: prompt,
            sampler: sampler,
            maxTokens: maxTokens
        )
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Build the Gemma chat prompt manually.
    ///
    /// We deliberately don't use LlamaKit's `applyChatTemplate`: this model's
    /// embedded template is a tool-calling Jinja macro template that neither
    /// llama.cpp's built-in formatter nor swift-jinja can render, so both paths
    /// throw. Gemma's wire format is simple and stable, and it has no system
    /// role — system text is folded into the first user turn. The tokenizer adds
    /// the leading BOS itself (`addSpecial: true` inside LlamaKit's generate),
    /// so we must not prepend `<bos>` here.
    private static func renderPrompt(system: String, user: String) -> String {
        "<start_of_turn>user\n\(system)\n\n\(user)<end_of_turn>\n<start_of_turn>model\n"
    }

    enum LlamaError: LocalizedError {
        case notReady(Status)
        var errorDescription: String? {
            switch self {
            case .notReady: return "The local model isn't ready yet."
            }
        }
    }
}
