import AppKit
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

// Text in, text out, through the model the user picked: Apple's on-device one (macOS 26, offline and free),
// Claude Code's own command line, or a local Ollama model.
enum Assistant {
    enum Engine: String, CaseIterable, Identifiable {
        case onDevice, claude, ollama
        var id: String { rawValue }
        var title: String {
            switch self {
            case .onDevice: "On-device"
            case .claude: "Claude Code"
            case .ollama: "Ollama"
            }
        }
    }

    struct Failure: LocalizedError {
        let errorDescription: String?
        init(_ text: String) { errorDescription = text }
    }

    static var onDeviceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), case .available = SystemLanguageModel.default.availability { return true }
        #endif
        return false
    }

    static var claudePath: String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return ["/opt/homebrew/bin/claude", "/usr/local/bin/claude", home + "/.claude/local/claude", home + "/.local/bin/claude"]
            .first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static var ollamaPath: String? {
        ["/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"].first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func available(_ engine: Engine) -> Bool {
        switch engine {
        case .onDevice: onDeviceAvailable
        case .claude: claudePath != nil
        case .ollama: ollamaPath != nil
        }
    }

    static func respond(_ prompt: String, instructions: String, engine: Engine) async throws -> String {
        switch engine {
        case .onDevice: try await onDevice(prompt, instructions: instructions)
        case .claude: try await claude(prompt, instructions: instructions)
        case .ollama: try await ollama(prompt, instructions: instructions)
        }
    }

    private static func onDevice(_ prompt: String, instructions: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), onDeviceAvailable {
            let session = LanguageModelSession(instructions: instructions)
            return try await session.respond(to: prompt).content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw Failure("Apple Intelligence isn't available on this Mac")
    }

    // `claude -p` answers once and exits. BEANIE_SELF tells Beanie's own hooks to ignore this session.
    private static func claude(_ prompt: String, instructions: String) async throws -> String {
        guard let path = claudePath else { throw Failure("Claude Code isn't installed") }
        return try await run(path, ["-p", instructions + "\n\n" + prompt], extraEnvironment: ["BEANIE_SELF": "1"], timeout: 180)
    }

    private static func ollama(_ prompt: String, instructions: String) async throws -> String {
        struct Tags: Decodable { struct Model: Decodable { let name: String }; let models: [Model] }
        struct Reply: Decodable { let response: String }
        let base = URL(string: "http://127.0.0.1:11434")!
        guard let (tagData, _) = try? await URLSession.shared.data(from: base.appendingPathComponent("api/tags")),
              let name = (try? JSONDecoder().decode(Tags.self, from: tagData))?.models.first?.name else {
            throw Failure("Ollama isn't running, or has no model pulled")
        }
        var request = URLRequest(url: base.appendingPathComponent("api/generate"), timeoutInterval: 180)
        request.httpMethod = "POST"
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": name, "prompt": prompt, "system": instructions, "stream": false])
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode(Reply.self, from: data).response.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func run(_ path: String, _ arguments: [String], extraEnvironment: [String: String], timeout: TimeInterval) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            process.environment = ProcessInfo.processInfo.environment.merging(extraEnvironment) { $1 }
            process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            process.standardInput = FileHandle.nullDevice
            process.terminationHandler = { p in
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                if p.terminationStatus == 0 {
                    continuation.resume(returning: text.trimmingCharacters(in: .whitespacesAndNewlines))
                } else {
                    let problem = String(decoding: err.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                    continuation.resume(throwing: Failure(problem.isEmpty ? "It stopped with an error" : String(problem.prefix(200))))
                }
            }
            do { try process.run() } catch { continuation.resume(throwing: error); return }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { if process.isRunning { process.terminate() } }
        }
    }

    // What a screenshot shows, read on the Mac.
    nonisolated static func text(in url: URL) async -> String {
        await Task.detached(priority: .utility) {
            guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                             kCGImageSourceThumbnailMaxPixelSize: 2000] as CFDictionary) else { return "" }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(cgImage: image).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        }.value
    }

    // "invoice-oktober-2026" from whatever the model said.
    static func slug(_ text: String) -> String {
        let cleaned = text.lowercased().split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let allowed = cleaned.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let joined = String(allowed).split(separator: "-").prefix(6).joined(separator: "-")
        return String(joined.prefix(60))
    }
}

// The canned clipboard actions.
enum TextAction: String, CaseIterable, Identifiable {
    case summarize, english, indonesian, grammar, explain
    var id: String { rawValue }
    var title: String {
        switch self {
        case .summarize: "Summarize"
        case .english: "Translate to English"
        case .indonesian: "Translate to Indonesian"
        case .grammar: "Fix grammar"
        case .explain: "Explain"
        }
    }
    var icon: String {
        switch self {
        case .summarize: "text.alignleft"
        case .english, .indonesian: "character.bubble"
        case .grammar: "checkmark.seal"
        case .explain: "lightbulb"
        }
    }
    var instructions: String {
        switch self {
        case .summarize: "Summarize the text in a few short sentences, in the text's own language. Reply with the summary only."
        case .english: "Translate the text into natural English. Reply with the translation only."
        case .indonesian: "Translate the text into natural Indonesian. Reply with the translation only."
        case .grammar: "Fix spelling, grammar and punctuation, keeping the meaning, language and tone. Reply with the corrected text only."
        case .explain: "Explain what the text means in plain words, briefly. If it is code, say what it does."
        }
    }
}
