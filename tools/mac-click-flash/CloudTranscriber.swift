import Foundation

final class CloudTranscriber {
    enum Failure: LocalizedError {
        case missingKey, invalidKey, http(Int), badResponse, timedOut
        var errorDescription: String? {
            switch self {
            case .missingKey: return "OpenAI APIキーをローカル設定してください"
            case .invalidKey: return "OpenAI APIキーの形式が不正です"
            case .http(let status): return "OpenAI STT: HTTP \(status)（認証・残高・モデル設定を確認）"
            case .badResponse: return "OpenAI STTの応答を解析できません"
            case .timedOut: return "OpenAI STTがタイムアウトしました"
            }
        }
    }
    static let defaultKeyFile = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(".config/pebble-click-flash/openai-api-key")
    private let keyFile: URL
    private let model: String
    init(keyFile: URL = CloudTranscriber.defaultKeyFile, model: String = "gpt-transcribe") {
        self.keyFile = keyFile
        self.model = model
    }
    func request(audio: Data, key: String) throws -> URLRequest {
        guard !key.isEmpty, !key.contains("\n"), !key.contains("\r") else { throw Failure.invalidKey }
        let boundary = "Pebble-\(UUID().uuidString)"
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        func field(_ name: String, _ value: String) {
            append("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n")
        }
        field("model", model)
        field("response_format", "json")
        append("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"audio.wav\"\r\nContent-Type: audio/wav\r\n\r\n")
        body.append(audio)
        append("\r\n--\(boundary)--\r\n")
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }
    static func text(from data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else { throw Failure.http(status) }
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else { throw Failure.badResponse }
        return text
    }
    // Called only on SpeechPipeline's background queue; never blocks BLE or animations.
    func transcribe(_ file: URL) throws -> String {
        let env = ProcessInfo.processInfo.environment["OPENAI_API_KEY"]
        let key = try (env ?? String(contentsOf: keyFile, encoding: .utf8))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw Failure.missingKey }
        let request = try self.request(audio: Data(contentsOf: file), key: key)
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForResource = 95
        let session = URLSession(configuration: config, delegate: NoRedirect(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        final class Response: @unchecked Sendable {
            var result: Swift.Result<String, Error>?
        }
        let response = Response()
        let done = DispatchSemaphore(value: 0)
        let task = session.dataTask(with: request) { data, reply, error in
            defer { done.signal() }
            if error != nil { response.result = .failure(Failure.badResponse); return }
            guard let data, let http = reply as? HTTPURLResponse else {
                response.result = .failure(Failure.badResponse); return
            }
            response.result = Swift.Result { try Self.text(from: data, status: http.statusCode) }
        }
        task.resume()
        guard done.wait(timeout: .now()+100) == .success else { task.cancel(); throw Failure.timedOut }
        return try response.result!.get()
    }
    private final class NoRedirect: NSObject, URLSessionTaskDelegate {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
}
