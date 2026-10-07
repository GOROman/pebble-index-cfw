import Foundation
import CryptoKit

final class DotsBridge {
    private struct Configuration: Decodable { let endpoint: URL; let token: String }
    private struct Pending: Codable { let id: String; let text: String; let device: String }
    private let queue = DispatchQueue(label: "pebble.dots-forwarding", qos: .utility)
    private let folder: URL
    private let configuration: URL
    private let log: (String, [String: Any]) -> Void
    private var retry: DispatchSourceTimer?
    private let session = URLSession(configuration: .ephemeral)

    init(log: @escaping (String, [String: Any]) -> Void) {
        self.log = log
        folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".config/pebble-click-flash/dots-outbox", isDirectory: true)
        configuration = folder.deletingLastPathComponent().appendingPathComponent("dots-bridge.json")
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now()+2, repeating: 30)
        timer.setEventHandler { [weak self] in self?.flush() }
        timer.resume(); retry = timer
    }
    deinit { retry?.cancel(); session.invalidateAndCancel() }
    func send(text: String, recording: URL) {
        guard FileManager.default.fileExists(atPath: configuration.path), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try FileManager.default.createDirectory(at: self.folder, withIntermediateDirectories: true, attributes: [.posixPermissions:0o700])
                let id = SHA256.hash(data: Data(recording.lastPathComponent.utf8)).map { String(format:"%02x",$0) }.joined()
                let pending = Pending(id:id, text:String(text.prefix(8000)), device:"pebble-index")
                let file = self.folder.appendingPathComponent(id).appendingPathExtension("json")
                try JSONEncoder().encode(pending).write(to:file, options:.atomic)
                try FileManager.default.setAttributes([.posixPermissions:0o600], ofItemAtPath:file.path)
                self.emit("dots-queued", ["id":id])
                self.flush()
            } catch { self.emit("dots-error", ["message":"送信待ち音声を保存できません"] ) }
        }
    }
    private func emit(_ event: String, _ fields: [String:Any]) {
        DispatchQueue.main.async { [weak self] in self?.log(event,fields) }
    }
    private var inFlight = Set<String>()
    private func flush() {
        guard let raw = try? Data(contentsOf:configuration), let config = try? JSONDecoder().decode(Configuration.self,from:raw),
              config.endpoint.scheme == "https", !config.token.isEmpty,
              let files = try? FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) else { return }
        for file in files where file.pathExtension == "json" && !inFlight.contains(file.lastPathComponent) {
            guard let data = try? Data(contentsOf:file), let pending = try? JSONDecoder().decode(Pending.self,from:data) else { continue }
            inFlight.insert(file.lastPathComponent)
            var request = URLRequest(url:config.endpoint)
            request.httpMethod = "POST"; request.timeoutInterval = 15
            request.setValue("Bearer \(config.token)",forHTTPHeaderField:"Authorization")
            request.setValue("application/json",forHTTPHeaderField:"Content-Type")
            request.httpBody = data
            session.dataTask(with:request) { [weak self] data, response, error in
                guard let self else { return }
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                self.queue.async {
                    self.inFlight.remove(file.lastPathComponent)
                    if error == nil, (200..<300).contains(status) {
                        try? FileManager.default.removeItem(at:file)
                        let payload = data.flatMap { try? JSONSerialization.jsonObject(with:$0) as? [String:Any] }
                        self.emit("dots-accepted", ["id":pending.id,"subscriptions":payload?["subscriptions"] as? Int ?? 0])
                    } else {
                        self.emit("dots-retry", ["id":pending.id,"status":status])
                    }
                }
            }.resume()
        }
    }
}
