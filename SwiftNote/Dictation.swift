//
//  Dictation.swift
//  SwiftNote — dictation with three engines: Apple Speech, whisper.cpp (local) and an
//  OpenAI-compatible Whisper API. Audio capture is kept off the main actor so the tap
//  callback never touches UI state.
//

import Foundation
import AVFoundation
import Speech
import Accelerate
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Errors
enum DictationError: LocalizedError {
    case noInput
    case recognizerUnavailable
    case config(String)
    case api(Int, String)
    case process(String)

    var errorDescription: String? {
        switch self {
        case .noInput:               return "No microphone input is available."
        case .recognizerUnavailable: return "Speech recognition isn't available for this language right now."
        case .config(let m):         return m
        case .api(let code, let m):  return "The transcription server returned \(code). \(m)"
        case .process(let m):        return m
        }
    }
}

// MARK: - Permissions
enum Permissions {
    static func requestMicrophone() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:    return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .audio)
        default:             return false
        }
    }

    static func requestSpeech() async -> Bool {
        switch SFSpeechRecognizer.authorizationStatus() {
        case .authorized: return true
        case .notDetermined:
            return await withCheckedContinuation { cont in
                SFSpeechRecognizer.requestAuthorization { status in cont.resume(returning: status == .authorized) }
            }
        default: return false
        }
    }

    static var microphoneGranted: Bool { AVCaptureDevice.authorizationStatus(for: .audio) == .authorized }
    static var speechGranted: Bool { SFSpeechRecognizer.authorizationStatus() == .authorized }

    static func openPrivacyPane(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Small thread-safe box
final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

// MARK: - Audio capture (not main-actor isolated)
final class AudioCapture: @unchecked Sendable {
    private let engine = AVAudioEngine()
    let level = LockedBox<Float>(0)
    private let sink = LockedBox<(@Sendable (AVAudioPCMBuffer) -> Void)?>(nil)
    private let format = LockedBox<AVAudioFormat?>(nil)

    var inputFormat: AVAudioFormat? { format.value }

    func setSink(_ handler: (@Sendable (AVAudioPCMBuffer) -> Void)?) { sink.value = handler }

    func start() throws {
        let input = engine.inputNode
        let fmt = input.outputFormat(forBus: 0)
        guard fmt.sampleRate > 0, fmt.channelCount > 0 else { throw DictationError.noInput }
        format.value = fmt
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: fmt) { [weak self] buffer, _ in
            self?.handle(buffer)
        }
        engine.prepare()
        try engine.start()
    }

    func stop() {
        engine.stop()
        engine.inputNode.removeTap(onBus: 0)
        level.value = 0
    }

    private func handle(_ buffer: AVAudioPCMBuffer) {
        if let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            vDSP_svesq(channel, 1, &sum, vDSP_Length(buffer.frameLength))
            level.value = sqrt(sum / Float(buffer.frameLength))
        }
        sink.value?(buffer)
    }
}

// MARK: - 16 kHz mono WAV writer (for Whisper)
final class WavSegmentWriter: @unchecked Sendable {
    private let lock = NSLock()
    private let dir: URL
    private let inputFormat: AVAudioFormat
    private let outFormat: AVAudioFormat
    private var converter: AVAudioConverter?
    private var file: AVAudioFile?
    private var currentURL: URL
    private var peak: Float = 0
    private var frames: Int = 0

    init(inputFormat: AVAudioFormat, dir: URL) throws {
        guard let out = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16000, channels: 1, interleaved: true) else {
            throw DictationError.config("Couldn't create the 16 kHz audio format.")
        }
        self.inputFormat = inputFormat
        self.outFormat = out
        self.dir = dir
        self.currentURL = dir.appendingPathComponent("seg-\(UUID().uuidString).wav")
        self.converter = AVAudioConverter(from: inputFormat, to: out)
        try openFile()
    }

    private func openFile() throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        file = try AVAudioFile(forWriting: currentURL, settings: settings,
                               commonFormat: .pcmFormatInt16, interleaved: true)
        peak = 0
        frames = 0
    }

    func append(_ buffer: AVAudioPCMBuffer) {
        lock.lock(); defer { lock.unlock() }
        guard let file = file, let converter = converter else { return }

        if let ch = buffer.floatChannelData?[0], buffer.frameLength > 0 {
            var sum: Float = 0
            vDSP_svesq(ch, 1, &sum, vDSP_Length(buffer.frameLength))
            peak = max(peak, sqrt(sum / Float(buffer.frameLength)))
        }

        let ratio = outFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
        guard let out = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) else { return }

        var supplied = false
        var error: NSError?
        converter.convert(to: out, error: &error) { _, status in
            if supplied {
                status.pointee = .noDataNow
                return nil
            }
            supplied = true
            status.pointee = .haveData
            return buffer
        }
        if error == nil, out.frameLength > 0 {
            try? file.write(from: out)
            frames += Int(out.frameLength)
        }
    }

    struct Segment { let url: URL; let peak: Float; let seconds: Double }

    /// Closes the current segment and starts a new one. Returns the finished segment (nil if it was empty).
    func rotate() -> Segment? {
        lock.lock(); defer { lock.unlock() }
        let finished = Segment(url: currentURL, peak: peak, seconds: Double(frames) / 16000.0)
        file = nil
        currentURL = dir.appendingPathComponent("seg-\(UUID().uuidString).wav")
        converter?.reset()
        try? openFile()
        if finished.seconds < 0.3 {
            try? FileManager.default.removeItem(at: finished.url)
            return nil
        }
        return finished
    }

    /// Closes the writer for good. Returns the last segment (nil if empty).
    func finish() -> Segment? {
        lock.lock(); defer { lock.unlock() }
        let finished = Segment(url: currentURL, peak: peak, seconds: Double(frames) / 16000.0)
        file = nil
        if finished.seconds < 0.3 {
            try? FileManager.default.removeItem(at: finished.url)
            return nil
        }
        return finished
    }

    func discard() {
        lock.lock(); defer { lock.unlock() }
        file = nil
        try? FileManager.default.removeItem(at: currentURL)
    }
}

// MARK: - Whisper configuration snapshot (value type so it can cross threads)
struct WhisperConfig: Sendable {
    var binaryPath: String
    var modelPath: String
    var threads: Int
    var language: String
    var translate: Bool
    var prompt: String
    var extraArgs: String
    var apiBase: String
    var apiModel: String
    var apiLanguage: String
    var apiPrompt: String
    var apiTemperature: Double
    var apiTimeout: Int
    var apiKey: String

    @MainActor
    static func current() -> WhisperConfig {
        let s = AppSettings.shared
        return WhisperConfig(binaryPath: s.whisperBinaryPath, modelPath: s.whisperModelPath,
                             threads: s.whisperThreads, language: s.whisperLanguage,
                             translate: s.whisperTranslate, prompt: s.whisperPrompt, extraArgs: s.whisperExtraArgs,
                             apiBase: s.whisperAPIBaseURL, apiModel: s.whisperAPIModel,
                             apiLanguage: s.whisperAPILanguage, apiPrompt: s.whisperAPIPrompt,
                             apiTemperature: s.whisperAPITemperature, apiTimeout: s.whisperAPITimeout,
                             apiKey: Keychain.get("whisperAPIKey") ?? "")
    }
}

// MARK: - Whisper runners
enum Whisper {
    static let binaryCandidates = [
        "/opt/homebrew/bin/whisper-cli", "/usr/local/bin/whisper-cli",
        "/opt/homebrew/bin/whisper-cpp", "/usr/local/bin/whisper-cpp",
        "/opt/homebrew/bin/whisper", "/usr/local/bin/whisper",
        NSHomeDirectory() + "/whisper.cpp/build/bin/whisper-cli",
        NSHomeDirectory() + "/whisper.cpp/main"
    ]

    static func detectBinary() -> String? {
        binaryCandidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func validateLocal(_ c: WhisperConfig) throws {
        guard !c.binaryPath.isEmpty, FileManager.default.isExecutableFile(atPath: c.binaryPath) else {
            throw DictationError.config("whisper.cpp isn't set up. Choose the whisper-cli binary in Settings → Whisper (Homebrew: brew install whisper-cpp).")
        }
        guard !c.modelPath.isEmpty, FileManager.default.fileExists(atPath: c.modelPath) else {
            throw DictationError.config("No Whisper model selected. Download or import a ggml model in Settings → Whisper.")
        }
    }

    static func validateAPI(_ c: WhisperConfig) throws {
        guard URL(string: c.apiBase.trimmingCharacters(in: .whitespaces)) != nil, !c.apiBase.isEmpty else {
            throw DictationError.config("The Whisper API base URL is invalid. Check Settings → Whisper.")
        }
    }

    static func transcribe(url: URL, engine: DictationEngine, config: WhisperConfig) async throws -> String {
        switch engine {
        case .whisperLocal: return try await runLocal(url: url, config: config)
        case .whisperAPI:   return try await runAPI(url: url, config: config)
        case .apple:        return ""
        }
    }

    // MARK: Local (whisper.cpp command line)
    static func splitArgs(_ s: String) -> [String] {
        var args: [String] = []
        var current = ""
        var quote: Character? = nil
        for ch in s {
            if let q = quote {
                if ch == q { quote = nil } else { current.append(ch) }
            } else if ch == "\"" || ch == "'" {
                quote = ch
            } else if ch == " " || ch == "\n" || ch == "\t" {
                if !current.isEmpty { args.append(current); current = "" }
            } else {
                current.append(ch)
            }
        }
        if !current.isEmpty { args.append(current) }
        return args
    }

    static func cleanOutput(_ raw: String) -> String {
        var text = raw
        for token in ["[BLANK_AUDIO]", "[MUSIC]", "(silence)", "[SILENCE]", "[ Silence ]", "(music)"] {
            text = text.replacingOccurrences(of: token, with: "", options: .caseInsensitive)
        }
        let lines = text.split(whereSeparator: { $0.isNewline }).map { $0.trimmingCharacters(in: .whitespaces) }
        return lines.filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func runLocal(url: URL, config c: WhisperConfig) async throws -> String {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: c.binaryPath)
                var args = ["-m", c.modelPath, "-f", url.path, "-t", String(max(1, c.threads)), "-nt", "-np"]
                args += ["-l", (c.language.isEmpty ? "auto" : c.language)]
                if c.translate { args.append("-tr") }
                if !c.prompt.isEmpty { args += ["--prompt", c.prompt] }
                args += splitArgs(c.extraArgs)
                process.arguments = args

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err
                let errBuffer = LockedBox<Data>(Data())
                err.fileHandleForReading.readabilityHandler = { handle in
                    let chunk = handle.availableData
                    if !chunk.isEmpty { errBuffer.value.append(chunk) }
                }
                do {
                    try process.run()
                } catch {
                    err.fileHandleForReading.readabilityHandler = nil
                    cont.resume(throwing: DictationError.process("Couldn't start whisper.cpp: \(error.localizedDescription)"))
                    return
                }
                let data = out.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                err.fileHandleForReading.readabilityHandler = nil

                if process.terminationStatus != 0 {
                    let tail = String(data: errBuffer.value, encoding: .utf8)?
                        .split(separator: "\n").suffix(3).joined(separator: " ") ?? ""
                    cont.resume(throwing: DictationError.process("whisper.cpp exited with code \(process.terminationStatus). \(tail)"))
                    return
                }
                let text = String(data: data, encoding: .utf8) ?? ""
                cont.resume(returning: cleanOutput(text))
            }
        }
    }

    // MARK: Online API (OpenAI-compatible /audio/transcriptions)
    static func endpoint(_ base: String, path: String) -> URL? {
        var b = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while b.hasSuffix("/") { b.removeLast() }
        return URL(string: b + path)
    }

    static func runAPI(url: URL, config c: WhisperConfig) async throws -> String {
        guard let endpoint = endpoint(c.apiBase, path: "/audio/transcriptions") else {
            throw DictationError.config("The Whisper API base URL is invalid.")
        }
        let boundary = "SwiftNote-\(UUID().uuidString)"
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = TimeInterval(max(5, c.apiTimeout))
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !c.apiKey.isEmpty { request.setValue("Bearer \(c.apiKey)", forHTTPHeaderField: "Authorization") }

        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", c.apiModel)
        field("response_format", "json")
        field("temperature", String(c.apiTemperature))
        if !c.apiLanguage.isEmpty { field("language", c.apiLanguage) }
        if !c.apiPrompt.isEmpty { field("prompt", c.apiPrompt) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(try Data(contentsOf: url))
        body.append(Data("\r\n--\(boundary)--\r\n".utf8))

        let (data, response) = try await URLSession.shared.upload(for: request, from: body)
        guard let http = response as? HTTPURLResponse else { throw DictationError.api(0, "No response.") }
        guard (200..<300).contains(http.statusCode) else {
            var message = String(data: data, encoding: .utf8) ?? ""
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let e = obj["error"] as? [String: Any], let m = e["message"] as? String { message = m }
            throw DictationError.api(http.statusCode, String(message.prefix(200)))
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any], let text = obj["text"] as? String {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return (String(data: data, encoding: .utf8) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Lightweight connectivity check: GET {base}/models.
    static func testAPI(_ c: WhisperConfig) async -> String {
        guard let url = endpoint(c.apiBase, path: "/models") else { return "❌ Invalid base URL" }
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        if !c.apiKey.isEmpty { request.setValue("Bearer \(c.apiKey)", forHTTPHeaderField: "Authorization") }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return "❌ No response" }
            switch http.statusCode {
            case 200..<300: return "✅ Connected (HTTP \(http.statusCode))"
            case 401, 403:  return "⚠️ Reached the server, but the API key was rejected (HTTP \(http.statusCode))"
            case 404:       return "⚠️ Reached the server, but /models wasn't found (HTTP 404). Transcription may still work."
            default:        return "⚠️ Server answered HTTP \(http.statusCode)"
            }
        } catch {
            return "❌ \(error.localizedDescription)"
        }
    }
}

// MARK: - Whisper model catalog / downloader
struct WhisperModelInfo: Identifiable {
    let id: String
    let title: String
    let note: String
    let sizeMB: Int

    var fileName: String { "ggml-\(id).bin" }
    var url: URL { URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(fileName)")! }
    var sizeText: String { sizeMB >= 1000 ? String(format: "%.1f GB", Double(sizeMB) / 1000) : "\(sizeMB) MB" }

    static let catalog: [WhisperModelInfo] = [
        WhisperModelInfo(id: "tiny.en", title: "Tiny (English)", note: "Fastest, lowest accuracy", sizeMB: 75),
        WhisperModelInfo(id: "base.en", title: "Base (English)", note: "Great speed / accuracy balance", sizeMB: 142),
        WhisperModelInfo(id: "base.en-q5_1", title: "Base (English, quantized)", note: "Smaller and quicker, tiny accuracy cost", sizeMB: 57),
        WhisperModelInfo(id: "small.en", title: "Small (English)", note: "Noticeably more accurate", sizeMB: 466),
        WhisperModelInfo(id: "small.en-q5_1", title: "Small (English, quantized)", note: "Good default for Apple Silicon", sizeMB: 181),
        WhisperModelInfo(id: "tiny", title: "Tiny (multilingual)", note: "99 languages, lowest accuracy", sizeMB: 75),
        WhisperModelInfo(id: "base", title: "Base (multilingual)", note: "99 languages", sizeMB: 142),
        WhisperModelInfo(id: "small", title: "Small (multilingual)", note: "99 languages, solid accuracy", sizeMB: 466),
        WhisperModelInfo(id: "medium", title: "Medium (multilingual)", note: "High accuracy, needs a fast Mac", sizeMB: 1500),
        WhisperModelInfo(id: "large-v3-turbo-q5_0", title: "Large v3 Turbo (quantized)", note: "Near-large accuracy, much faster", sizeMB: 574),
        WhisperModelInfo(id: "large-v3-turbo", title: "Large v3 Turbo", note: "Best speed / accuracy at the top end", sizeMB: 1620),
        WhisperModelInfo(id: "large-v3", title: "Large v3", note: "Most accurate, slowest", sizeMB: 3100)
    ]
}

@MainActor
final class WhisperModelManager: NSObject, ObservableObject {
    static let shared = WhisperModelManager()

    @Published private(set) var installed: [StoredFile] = []
    @Published private(set) var downloadingID: String?
    @Published private(set) var progress: Double = 0
    @Published var message: String = ""

    private var session: URLSession!

    private override init() {
        super.init()
        session = URLSession(configuration: .default, delegate: self, delegateQueue: .main)
        refresh()
    }

    func refresh() {
        installed = FileStore.list(AppPaths.models, exts: ["bin"])
    }

    func isInstalled(_ info: WhisperModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: AppPaths.models.appendingPathComponent(info.fileName).path)
    }

    func download(_ info: WhisperModelInfo) {
        guard downloadingID == nil else { return }
        downloadingID = info.id
        progress = 0
        message = "Downloading \(info.title)…"
        let task = session.downloadTask(with: info.url)
        task.taskDescription = info.fileName
        task.resume()
    }

    func cancelDownload() {
        session.getAllTasks { tasks in tasks.forEach { $0.cancel() } }
        downloadingID = nil
        message = "Download cancelled"
    }

    func importModel() {
        guard let src = Panels.chooseAnyFile(title: "Import Whisper Model",
                                             message: "Choose a whisper.cpp ggml model file (ggml-*.bin).") else { return }
        let dest = AppPaths.models.appendingPathComponent(src.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) { try FileManager.default.removeItem(at: dest) }
            try FileManager.default.copyItem(at: src, to: dest)
            message = "✅ Imported \(src.lastPathComponent)"
            refresh()
            select(dest)
        } catch {
            message = "❌ Import failed: \(error.localizedDescription)"
        }
    }

    func select(_ url: URL) {
        AppSettings.shared.whisperModelPath = url.path
    }

    func delete(_ file: StoredFile) {
        try? FileManager.default.removeItem(at: file.url)
        if AppSettings.shared.whisperModelPath == file.url.path { AppSettings.shared.whisperModelPath = "" }
        refresh()
    }

    fileprivate func finish(name: String, error: Error?) {
        downloadingID = nil
        if let error = error {
            message = "❌ Download failed: \(error.localizedDescription)"
        } else {
            message = "✅ Downloaded \(name)"
            refresh()
            if AppSettings.shared.whisperModelPath.isEmpty {
                select(AppPaths.models.appendingPathComponent(name))
            }
        }
    }
}

extension WhisperModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let p = totalBytesExpectedToWrite > 0 ? Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0
        Task { @MainActor in self.progress = p }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        let name = downloadTask.taskDescription ?? "model.bin"
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let err = DictationError.api(status, "The model couldn't be downloaded.")
            Task { @MainActor in self.finish(name: name, error: err) }
            return
        }
        let dest = AppPaths.models.appendingPathComponent(name)
        try? FileManager.default.removeItem(at: dest)
        do {
            try FileManager.default.moveItem(at: location, to: dest)
            Task { @MainActor in self.finish(name: name, error: nil) }
        } catch {
            Task { @MainActor in self.finish(name: name, error: error) }
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error = error else { return }
        let name = task.taskDescription ?? ""
        Task { @MainActor in self.finish(name: name, error: error) }
    }
}

// MARK: - Transcript clean-up (punctuation words, fillers, macros, capitalisation)
@MainActor
enum TranscriptCleaner {
    static func shouldCapitalise(after text: String) -> Bool {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t.isEmpty { return true }
        if text.hasSuffix("\n") { return true }
        guard let last = t.last else { return true }
        return ".!?".contains(last)
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let re = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return text }
        return re.stringByReplacingMatches(in: text, options: [], range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }

    static func clean(_ raw: String, capitaliseFirst: Bool) -> String {
        let s = AppSettings.shared
        var text = raw

        if s.fillerRemoval {
            let words = s.fillerWords.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            if !words.isEmpty {
                let alt = words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
                text = replace("\\b(\(alt))\\b", in: text, with: "")
            }
        }
        if s.voiceAllCaps { text = applyAllCaps(text) }
        if s.voicePunctuation {
            let map: [(String, String)] = [
                ("\\bopen quotes\\b", "\""), ("\\bclose quotes\\b", "\""),
                ("\\bopen paren\\b", "("), ("\\bclose paren\\b", ")"),
                ("\\bexclamation mark\\b", "!"), ("\\bquestion mark\\b", "?"),
                ("\\bsemicolon\\b", ";"), ("\\bcolon\\b", ":"),
                ("\\bcomma\\b", ","), ("\\bperiod\\b", "."),
                ("\\bdash\\b", "—"), ("\\bhyphen\\b", "-"), ("\\bellipsis\\b", "…")
            ]
            for (pattern, rep) in map { text = replace(pattern, in: text, with: rep) }
        }
        if s.voiceMacros {
            text = replace("\\bnew paragraph\\b", in: text, with: "\n\n")
            text = replace("\\bnew line\\b", in: text, with: "\n")
        }
        for p in [" ,", " .", " !", " ?", " ;", " :"] {
            text = text.replacingOccurrences(of: p, with: String(p.dropFirst()))
        }
        text = replace(" {2,}", in: text, with: " ")
        text = text.trimmingCharacters(in: .whitespaces)
        if s.autoCapitalise { text = capitalise(text, first: capitaliseFirst) }
        return text
    }

    private static func applyAllCaps(_ input: String) -> String {
        guard let re = try? NSRegularExpression(pattern: "all caps(.+?)end caps",
                                                options: [.caseInsensitive, .dotMatchesLineSeparators]) else { return input }
        var result = input
        let matches = re.matches(in: input, options: [], range: NSRange(input.startIndex..., in: input))
        for m in matches.reversed() where m.numberOfRanges > 1 {
            if let whole = Range(m.range, in: result), let inner = Range(m.range(at: 1), in: input) {
                result.replaceSubrange(whole, with: input[inner].uppercased())
            }
        }
        return replace("\\b(all caps|end caps)\\b", in: result, with: "")
    }

    private static func capitalise(_ text: String, first: Bool) -> String {
        var chars = Array(text)
        var needsCap = first
        for i in chars.indices {
            if needsCap, chars[i].isLetter {
                chars[i] = Character(chars[i].uppercased())
                needsCap = false
            } else if ".!?".contains(chars[i]) {
                needsCap = true
            } else if chars[i] == "\n" {
                needsCap = true
            } else if !chars[i].isWhitespace && !"\"')".contains(chars[i]) {
                needsCap = false
            }
        }
        return String(chars)
    }
}

// MARK: - Dictation manager
@MainActor
final class DictationManager: ObservableObject {
    static let shared = DictationManager()

    @Published private(set) var isRecording = false
    @Published private(set) var isTranscribing = false
    @Published private(set) var levels: [CGFloat] = Array(repeating: 0.04, count: 30)
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var activeEngine: DictationEngine = .apple
    @Published var errorMessage: String?

    private let settings = AppSettings.shared
    private let capture = AudioCapture()

    // Target text (quick note by default; the manager can aim it at a sticky note)
    private var getText: () -> String = { NoteManager.shared.noteText }
    private var setText: (String) -> Void = { NoteManager.shared.noteText = $0 }

    private var levelTimer: Timer?
    private var startDate: Date?
    private var sessionTranscript = ""
    private var starting = false

    // Apple Speech
    private var recognizer: SFSpeechRecognizer?
    private var task: SFSpeechRecognitionTask?
    private let requestBox = LockedBox<SFSpeechAudioBufferRecognitionRequest?>(nil)
    private var base = ""
    private var spacer = ""
    private var lastTranscription = ""
    private var finalizing = false
    private var quickFailures = 0
    private var taskStarted = Date()

    // Whisper
    private var writer: WavSegmentWriter?
    private var chunkTimer: Timer?
    private var transcribeChain: Task<Void, Never>?
    private var pendingTranscriptions = 0

    private init() {}

    var isBusy: Bool { isRecording || isTranscribing || starting }

    // MARK: Start / stop
    func start(into getText: (() -> String)? = nil, set setText: ((String) -> Void)? = nil) {
        guard settings.dictationEnabled else {
            ToastCenter.shared.show("Dictation is turned off in Settings")
            return
        }
        guard !isRecording, !starting, !(isTranscribing && settings.dictationEngine != .apple) else { return }
        self.getText = getText ?? { NoteManager.shared.noteText }
        self.setText = setText ?? { NoteManager.shared.noteText = $0 }
        starting = true
        errorMessage = nil
        Task { await self.begin() }
    }

    func toggle() {
        if isRecording { stop() } else { start() }
    }

    private func begin() async {
        defer { starting = false }
        let engine = settings.dictationEngine

        guard await Permissions.requestMicrophone() else {
            fail("Microphone access is off. Enable it in System Settings → Privacy & Security → Microphone.")
            return
        }
        if engine == .apple, !(await Permissions.requestSpeech()) {
            fail("Speech Recognition access is off. Enable it in System Settings → Privacy & Security → Speech Recognition.")
            return
        }

        activeEngine = engine
        sessionTranscript = ""
        do {
            switch engine {
            case .apple: try startApple()
            case .whisperLocal, .whisperAPI: try startWhisper(engine)
            }
        } catch {
            capture.stop()
            capture.setSink(nil)
            fail(error.localizedDescription)
            return
        }
        isRecording = true
        elapsed = 0
        startDate = Date()
        startLevelTimer()
        SoundManager.shared.play(.dictationStart)
    }

    func stop(discard: Bool = false) {
        guard isRecording else { return }
        stopLevelTimer()
        SoundManager.shared.play(.dictationStop)
        switch activeEngine {
        case .apple: stopApple(discard: discard)
        case .whisperLocal, .whisperAPI: stopWhisper(discard: discard)
        }
    }

    /// Stops, commits and saves the whole dictation transcript as a Markdown file.
    func stopAndSave() {
        guard isRecording else { return }
        let before = getText()
        let target = getText
        stop()
        // Give the engine a moment to finalise, then save what was dictated this session.
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            while self.isTranscribing { try? await Task.sleep(nanoseconds: 300_000_000) }
            let after = target()
            var dictated = after
            if after.hasPrefix(before) { dictated = String(after.dropFirst(before.count)) }
            NoteManager.shared.saveMarkdown(text: dictated.trimmed().isEmpty ? after : dictated, titleHint: "Dictation")
        }
    }

    private func fail(_ message: String) {
        errorMessage = message
        ToastCenter.shared.show("❌ \(message)", seconds: 5)
    }

    private func finishSession() {
        let transcript = sessionTranscript.trimmingCharacters(in: .whitespacesAndNewlines)
        sessionTranscript = ""
        guard settings.dictationSaveHistory, !transcript.isEmpty else { return }
        NoteManager.shared.addDictationSession(
            DictationSession(transcript: transcript, locale: settings.dictationLocale, engine: activeEngine.rawValue))
    }

    // MARK: Level meter
    private func startLevelTimer() {
        stopLevelTimer()
        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 24.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func stopLevelTimer() {
        levelTimer?.invalidate()
        levelTimer = nil
        levels = Array(repeating: 0.04, count: levels.count)
    }

    private func tick() {
        guard isRecording else { return }
        let rms = capture.level.value
        let gate = Float(settings.micGate)
        let value: CGFloat
        if rms < gate {
            value = 0.04
        } else {
            value = CGFloat(min(1.0, max(0.06, pow(Double(rms) * 14.0, 0.7))))
        }
        var next = levels
        next.removeFirst()
        next.append(value)
        levels = next

        if let start = startDate { elapsed = Date().timeIntervalSince(start) }
        let limit = settings.dictationMaxSeconds
        if limit > 0, elapsed >= Double(limit) { stop() }
    }

    // MARK: Apple Speech
    private func startApple() throws {
        let locale = Locale(identifier: settings.dictationLocale)
        guard let rec = SFSpeechRecognizer(locale: locale), rec.isAvailable else { throw DictationError.recognizerUnavailable }
        recognizer = rec

        let current = getText()
        base = current
        spacer = (current.isEmpty || current.hasSuffix(" ") || current.hasSuffix("\n")) ? "" : " "
        lastTranscription = ""
        finalizing = false
        quickFailures = 0
        startAppleTask()

        let box = requestBox
        capture.setSink { buffer in box.value?.append(buffer) }
        try capture.start()
    }

    private func startAppleTask() {
        guard let rec = recognizer else { return }
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if settings.appleOnDevice && rec.supportsOnDeviceRecognition { request.requiresOnDeviceRecognition = true }
        request.addsPunctuation = settings.appleAutoPunctuation
        let hints = settings.appleHints.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !hints.isEmpty { request.contextualStrings = hints }

        requestBox.value = request
        task?.cancel()
        taskStarted = Date()
        task = rec.recognitionTask(with: request) { @Sendable [weak self] result, error in
            let text = result?.bestTranscription.formattedString
            let isFinal = result?.isFinal ?? false
            let failed = error != nil
            Task { @MainActor in self?.handleApple(text: text, isFinal: isFinal, failed: failed) }
        }
    }

    private func handleApple(text: String?, isFinal: Bool, failed: Bool) {
        guard isRecording || finalizing else { return }
        if let t = text { applyApple(t) }
        guard (isFinal || failed), isRecording, activeEngine == .apple else { return }

        // The task ended on its own (about a minute of audio, or a "no speech" timeout) — commit and keep listening.
        if Date().timeIntervalSince(taskStarted) < 1.0 { quickFailures += 1 } else { quickFailures = 0 }
        if quickFailures >= 3 {
            stop()
            fail("Speech recognition stopped unexpectedly. Try again, or switch engines in Settings → Dictation.")
            return
        }
        sessionTranscript += (sessionTranscript.isEmpty ? "" : " ") + lastTranscription
        let current = getText()
        base = current
        spacer = (current.isEmpty || current.hasSuffix(" ") || current.hasSuffix("\n")) ? "" : " "
        lastTranscription = ""
        startAppleTask()
    }

    private func applyApple(_ raw: String) {
        let cleaned = TranscriptCleaner.clean(raw, capitaliseFirst: TranscriptCleaner.shouldCapitalise(after: base))
        let current = getText()
        let previousSuffix = lastTranscription.isEmpty ? "" : spacer + lastTranscription
        var newBase = current
        if !previousSuffix.isEmpty, current.hasSuffix(previousSuffix) {
            newBase = String(current.dropLast(previousSuffix.count))
        }
        lastTranscription = cleaned
        setText(newBase + (cleaned.isEmpty ? "" : spacer + cleaned))
    }

    private func stopApple(discard: Bool) {
        capture.stop()
        capture.setSink(nil)
        requestBox.value?.endAudio()
        isRecording = false

        if discard {
            removeLastAppleText()
            task?.cancel()
            task = nil
            requestBox.value = nil
            lastTranscription = ""
            sessionTranscript = ""
            return
        }
        finalizing = true
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            self.finishApple()
        }
    }

    private func finishApple() {
        finalizing = false
        task?.cancel()
        task = nil
        requestBox.value = nil
        sessionTranscript += (sessionTranscript.isEmpty ? "" : " ") + lastTranscription
        lastTranscription = ""
        finishSession()
    }

    private func removeLastAppleText() {
        guard !lastTranscription.isEmpty else { return }
        let suffix = spacer + lastTranscription
        let current = getText()
        if current.hasSuffix(suffix) { setText(String(current.dropLast(suffix.count))) } else { setText(base) }
    }

    // MARK: Whisper (local + API)
    private func startWhisper(_ engine: DictationEngine) throws {
        let config = WhisperConfig.current()
        if engine == .whisperLocal { try Whisper.validateLocal(config) } else { try Whisper.validateAPI(config) }

        try capture.start()
        guard let format = capture.inputFormat else { throw DictationError.noInput }
        let w = try WavSegmentWriter(inputFormat: format, dir: AppPaths.recordings)
        writer = w
        capture.setSink { buffer in w.append(buffer) }

        let chunk = settings.whisperChunkSeconds
        if chunk > 0 {
            chunkTimer = Timer.scheduledTimer(withTimeInterval: TimeInterval(chunk), repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.rotateChunk() }
            }
        }
    }

    private func rotateChunk() {
        guard isRecording, let segment = writer?.rotate() else { return }
        enqueue(segment)
    }

    private func stopWhisper(discard: Bool) {
        chunkTimer?.invalidate()
        chunkTimer = nil
        capture.stop()
        capture.setSink(nil)
        isRecording = false
        let w = writer
        writer = nil

        if discard {
            w?.discard()
            return
        }
        if let segment = w?.finish() {
            enqueue(segment)
        } else if pendingTranscriptions == 0 {
            finishSession()
        }
    }

    private func enqueue(_ segment: WavSegmentWriter.Segment) {
        // Skip clips that are essentially silence — they make Whisper hallucinate.
        guard segment.peak > 0.003 else {
            try? FileManager.default.removeItem(at: segment.url)
            if !isRecording && pendingTranscriptions == 0 { finishSession() }
            return
        }
        pendingTranscriptions += 1
        isTranscribing = true
        let previous = transcribeChain
        let engine = activeEngine
        let config = WhisperConfig.current()
        let url = segment.url
        transcribeChain = Task { [weak self] in
            await previous?.value
            var result: Result<String, Error>
            do { result = .success(try await Whisper.transcribe(url: url, engine: engine, config: config)) }
            catch { result = .failure(error) }
            try? FileManager.default.removeItem(at: url)
            await self?.completeTranscription(result)
        }
    }

    private func completeTranscription(_ result: Result<String, Error>) {
        pendingTranscriptions = max(0, pendingTranscriptions - 1)
        switch result {
        case .success(let raw):
            let current = getText()
            let cleaned = TranscriptCleaner.clean(raw, capitaliseFirst: TranscriptCleaner.shouldCapitalise(after: current))
            if !cleaned.isEmpty {
                let sp = (current.isEmpty || current.hasSuffix(" ") || current.hasSuffix("\n")) ? "" : " "
                setText(current + sp + cleaned)
                sessionTranscript += (sessionTranscript.isEmpty ? "" : " ") + cleaned
            }
        case .failure(let error):
            fail(error.localizedDescription)
        }
        if pendingTranscriptions == 0 {
            isTranscribing = false
            if !isRecording { finishSession() }
        }
    }
}
