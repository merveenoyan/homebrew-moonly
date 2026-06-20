import Foundation
import Combine
import Darwin
import AppKit

/// Manages a local `llama-server` child process serving Gemma 4 E4B (QAT) and
/// talks to it over its OpenAI-compatible HTTP API.
///
/// Design follows ggml-org's Llama.app: we don't bundle the engine, we share
/// the Homebrew `llama.cpp` install, and we let llama.cpp's own `-hf` flag
/// handle download + cache + serve in a single command:
///
///     llama-server -hf google/gemma-4-E4B-it-qat-q4_0-gguf
///
/// The model is cached under the app's Application Support dir (LLAMA_CACHE),
/// the server is bound to 127.0.0.1 on an ephemeral port, and the app makes no
/// other network calls. Nothing leaves the machine except the one-time,
/// inbound model download from Hugging Face.
@MainActor
final class LlamaServer: ObservableObject {
    static let shared = LlamaServer()

    /// The single source of model truth — passed straight to `-hf`.
    static let modelRepo = "google/gemma-4-E4B-it-qat-q4_0-gguf"

    enum Status: Equatable {
        case idle            // not started yet
        case missingBinary   // llama-server not found (llama.cpp not installed)
        case starting        // launching / loading / downloading on first run
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

    private var process: Process?
    private var port: UInt16 = 0
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.timeoutIntervalForRequest = 300
        cfg.waitsForConnectivity = false
        return URLSession(configuration: cfg)
    }()

    private init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main
        ) { [weak self] _ in self?.process?.terminate() }
    }

    // MARK: - Filesystem locations

    /// App-owned model cache. Passed to llama.cpp via the LLAMA_CACHE env var so
    /// the GGUF lives somewhere predictable and `brew uninstall` can wipe it.
    static var cacheDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Moonly/models", isDirectory: true)
    }

    /// Best-effort check for whether anything has been downloaded yet, so the UI
    /// can warn that first launch will pull ~5 GB.
    var modelLikelyCached: Bool { resolveCachedModel() != nil }

    /// The GGUF files already present in the local HF cache, if any. The main
    /// weights are the `.gguf` without "mmproj" in the name; the multimodal
    /// projector (optional) is the one that does. Resolving these lets us launch
    /// straight from disk with `-m`/`--mmproj` and never touch the network.
    private func resolveCachedModel() -> (model: URL, mmproj: URL?)? {
        let fm = FileManager.default
        guard let walker = fm.enumerator(at: Self.cacheDir,
                                         includingPropertiesForKeys: [.isRegularFileKey],
                                         options: [.skipsHiddenFiles]) else { return nil }
        var model: URL?
        var mmproj: URL?
        for case let url as URL in walker where url.pathExtension == "gguf" {
            // Follow symlinks (HF stores snapshots as links into blobs/) and
            // skip anything that doesn't actually resolve to a file.
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true
                || fm.fileExists(atPath: url.resolvingSymlinksInPath().path) else { continue }
            if url.lastPathComponent.localizedCaseInsensitiveContains("mmproj") {
                mmproj = mmproj ?? url
            } else {
                model = model ?? url
            }
        }
        guard let model else { return nil }
        return (model, mmproj)
    }

    /// Resolve `llama-server`: bundled copy first (if a future build ships one),
    /// then the Homebrew install locations, then PATH.
    private func resolveBinary() -> URL? {
        let candidates = [
            Bundle.main.resourceURL?.appendingPathComponent("bin/llama-server"),
            URL(fileURLWithPath: "/opt/homebrew/bin/llama-server"),
            URL(fileURLWithPath: "/usr/local/bin/llama-server"),
        ].compactMap { $0 }

        let fm = FileManager.default
        if let found = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) { return found }
        if let path = ProcessInfo.processInfo.environment["PATH"] {
            for dir in path.split(separator: ":") {
                let c = URL(fileURLWithPath: String(dir)).appendingPathComponent("llama-server")
                if fm.isExecutableFile(atPath: c.path) { return c }
            }
        }
        return nil
    }

    // MARK: - Lifecycle

    /// Idempotently bring the server up. Safe to call repeatedly.
    func ensureRunning() async {
        switch status {
        case .ready, .generating, .starting: return
        default: break
        }

        guard let binary = resolveBinary() else { status = .missingBinary; return }

        try? FileManager.default.createDirectory(at: Self.cacheDir, withIntermediateDirectories: true)

        let cached = resolveCachedModel()
        status = .starting
        detail = cached != nil ? "Loading model…" : "Downloading model (~5 GB, first run only)…"
        port = Self.freePort()

        // Prefer the already-downloaded files: launch with `-m`/`--mmproj` so
        // llama.cpp never contacts Hugging Face. Only fall back to `-hf` (which
        // checks the repo and downloads) when nothing is cached yet.
        var modelArgs: [String]
        if let cached {
            modelArgs = ["-m", cached.model.path]
            if let mmproj = cached.mmproj {
                modelArgs += ["--mmproj", mmproj.path]
            }
        } else {
            modelArgs = ["-hf", Self.modelRepo]
        }

        let proc = Process()
        proc.executableURL = binary
        proc.arguments = modelArgs + [
            "--host", "127.0.0.1",
            "--port", String(port),
            "-c", "4096",
            "-ngl", "999",           // offload all layers to Metal on Apple Silicon
            "--jinja",               // use Gemma's embedded chat template
            "--no-webui",
        ]
        var env = ProcessInfo.processInfo.environment
        env["LLAMA_CACHE"] = Self.cacheDir.path
        proc.environment = env

        // Tail stderr so we can show "Downloading…" vs "Loading…" in the UI.
        let errPipe = Pipe()
        proc.standardOutput = FileHandle.nullDevice
        proc.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            guard let line = String(data: handle.availableData, encoding: .utf8), !line.isEmpty else { return }
            let lower = line.lowercased()
            Task { @MainActor in
                guard let self, self.status == .starting else { return }
                if lower.contains("download") || lower.contains("%") {
                    self.detail = "Downloading model (~5 GB, first run only)…"
                } else if lower.contains("loading model") || lower.contains("load_tensors") {
                    self.detail = "Loading model…"
                }
            }
        }

        proc.terminationHandler = { [weak self] p in
            Task { @MainActor in
                guard let self, self.process === p else { return }
                if self.status != .idle {
                    self.status = .failed("llama-server exited (code \(p.terminationStatus))")
                    self.detail = nil
                }
                self.process = nil
            }
        }

        do {
            try proc.run()
            self.process = proc
        } catch {
            status = .failed("Couldn't launch llama-server: \(error.localizedDescription)")
            return
        }

        // First run may download several GB, so allow a long startup window.
        await waitForHealth(timeout: modelLikelyCached ? 120 : 3600)
        errPipe.fileHandleForReading.readabilityHandler = nil
    }

    private func waitForHealth(timeout: TimeInterval) async {
        let deadline = Date().addingTimeInterval(timeout)
        let healthURL = URL(string: "http://127.0.0.1:\(port)/health")!
        while Date() < deadline {
            if process?.isRunning != true {
                status = .failed("llama-server stopped during startup"); detail = nil; return
            }
            if let (_, resp) = try? await session.data(from: healthURL),
               (resp as? HTTPURLResponse)?.statusCode == 200 {
                status = .ready; detail = nil; return
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
        }
        status = .failed("llama-server didn't become ready in time"); detail = nil
    }

    func stop() {
        process?.terminate()
        process = nil
        status = .idle
        detail = nil
    }

    // MARK: - Chat

    struct ChatMessage: Codable { let role: String; let content: String }

    /// Send a chat completion request and return the assistant's text.
    func chat(system: String, user: String,
              temperature: Double = 0.7, maxTokens: Int = 400) async throws -> String {
        if !status.isUsable { await ensureRunning() }
        guard status.isUsable else { throw LlamaError.notReady(status) }

        status = .generating
        defer { if status == .generating { status = .ready } }

        struct Request: Codable {
            let model: String
            let messages: [ChatMessage]
            let temperature: Double
            let top_p: Double
            let top_k: Int
            let max_tokens: Int
            let stream: Bool
        }
        let body = Request(
            model: "gemma-4-e4b",
            messages: [.init(role: "system", content: system),
                       .init(role: "user", content: user)],
            temperature: temperature, top_p: 0.95, top_k: 64,
            max_tokens: maxTokens, stream: false
        )

        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/v1/chat/completions")!)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(body)

        let (data, resp) = try await session.data(for: req)
        guard (resp as? HTTPURLResponse)?.statusCode == 200 else {
            throw LlamaError.badResponse((resp as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct Response: Codable {
            struct Choice: Codable { struct Msg: Codable { let content: String }; let message: Msg }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(Response.self, from: data)
        return (decoded.choices.first?.message.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    enum LlamaError: LocalizedError {
        case notReady(Status)
        case badResponse(Int)
        var errorDescription: String? {
            switch self {
            case .notReady:           return "The local model isn't ready yet."
            case .badResponse(let c): return "Model server returned HTTP \(c)."
            }
        }
    }

    // MARK: - Free port

    /// Ask the kernel for an unused loopback port by binding to port 0.
    private static func freePort() -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return 49207 }
        defer { close(fd) }

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")
        addr.sin_port = 0

        let bound = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { return 49207 }

        var len = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &len) }
        }
        return UInt16(bigEndian: addr.sin_port)
    }
}
