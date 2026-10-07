import Foundation
import Darwin

final class SpeechPipeline {
    struct Result {
        let text: String
        let cleanedAudio: URL
        let transcript: URL
        let elapsed: TimeInterval
    }
    enum Failure: LocalizedError {
        case unavailable(String), failed(String), timedOut
        var errorDescription: String? {
            switch self {
            case .unavailable(let item): return "見つかりません: \(item)"
            case .failed(let message): return message
            case .timedOut: return "音声認識がタイムアウトしました"
            }
        }
    }
    private let queue = DispatchQueue(label: "pebble.local-speech", qos: .userInitiated)
    private let model: URL
    private let ffmpeg: URL
    private let whisper: URL

    init(model: URL, ffmpeg: URL, whisper: URL) {
        self.model = model
        self.ffmpeg = ffmpeg
        self.whisper = whisper
    }

    func transcribe(_ recording: URL, status: @escaping (String) -> Void,
                    completion: @escaping (Swift.Result<Result, Error>) -> Void) {
        queue.async {
            let start = Date()
            do {
                for file in [self.model, self.ffmpeg, self.whisper] {
                    guard FileManager.default.fileExists(atPath: file.path) else {
                        throw Failure.unavailable(file.path)
                    }
                }
                let stem = recording.deletingPathExtension()
                let cleaned = stem.appendingPathExtension("clean.wav")
                let output = stem.appendingPathExtension("transcript")
                let trace = stem.appendingPathExtension("stt.log")
                FileManager.default.createFile(atPath: trace.path, contents: nil)
                let traceFile = try FileHandle(forWritingTo: trace)
                defer { try? traceFile.close() }
                DispatchQueue.main.async { status("ノイズ低減中…") }
                try self.run(self.ffmpeg, [
                    "-hide_banner", "-loglevel", "error", "-y", "-i", recording.path,
                    "-af", "highpass=f=90,lowpass=f=3800,afftdn=nr=12:nf=-35:tn=1,dynaudnorm=f=150:g=7:p=0.85",
                    "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", cleaned.path,
                ], trace: traceFile)
                DispatchQueue.main.async { status("日本語を文字起こし中…") }
                try self.run(self.whisper, [
                    "-m", self.model.path, "-f", cleaned.path, "-l", "ja", "-nt", "-nf",
                    "-bo", "2", "-bs", "2", "-otxt", "-oj", "-of", output.path,
                ], trace: traceFile)
                let transcript = output.appendingPathExtension("txt")
                let rawText = try String(contentsOf: transcript, encoding: .utf8)
                let result = Result(text: Self.displayText(rawText), cleanedAudio: cleaned,
                                    transcript: transcript, elapsed: Date().timeIntervalSince(start))
                DispatchQueue.main.async { completion(.success(result)) }
            } catch {
                DispatchQueue.main.async { completion(.failure(error)) }
            }
        }
    }

    static func displayText(_ raw: String) -> String {
        // Whisper can emit sound descriptions instead of speech. Keep them in the saved
        // transcript, but don't scroll e.g. "(マイクの音)" as if someone said it.
        let annotations = #"\[[^\]]*\]|\([^)]*\)|（[^）]*）|【[^】]*】|<\|[^>]*\|>"#
        let stripped = raw.replacingOccurrences(of: annotations, with: "", options: .regularExpression)
        let text = stripped.split(whereSeparator: { $0.isNewline }).map(String.init)
            .joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.unicodeScalars.contains(where: { CharacterSet.alphanumerics.contains($0) }) else { return "" }
        return String(text.prefix(240))
    }

    private func run(_ executable: URL, _ arguments: [String], trace: FileHandle) throws {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = trace
        process.standardError = trace
        let done = DispatchGroup()
        done.enter()
        process.terminationHandler = { _ in done.leave() }
        try process.run()
        if done.wait(timeout: .now() + 120) == .timedOut {
            process.terminate()
            if done.wait(timeout: .now() + 2) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = done.wait(timeout: .now() + 5)
            }
            throw Failure.timedOut
        }
        guard process.terminationStatus == 0 else {
            throw Failure.failed("\(executable.lastPathComponent) が終了コード \(process.terminationStatus) で失敗しました（stt.log参照）")
        }
    }
}
