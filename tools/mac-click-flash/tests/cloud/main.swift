import Foundation
let cloud = CloudTranscriber()
let pcm = Data([0, 1, 2, 3])
let request = try cloud.request(audio: pcm, key: "test-placeholder")
assert(request.url?.absoluteString == "https://api.openai.com/v1/audio/transcriptions")
assert(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-placeholder")
let body = request.httpBody!
assert(body.range(of: pcm) != nil)
assert(String(data: body, encoding: .utf8)!.contains("gpt-transcribe"))
let decoded = try CloudTranscriber.text(from: Data("{\"text\":\"こんにちは\"}".utf8), status: 200)
assert(decoded == "こんにちは")
do { _ = try cloud.request(audio: pcm, key: "bad\nheader"); fatalError("invalid key accepted") } catch {}
do { _ = try CloudTranscriber.text(from: Data("{}".utf8), status: 401); fatalError("HTTP error accepted") } catch {}
do { _ = try CloudTranscriber.text(from: Data("{}".utf8), status: 200); fatalError("bad response accepted") } catch {}
print("Cloud request, Japanese result, invalid key, HTTP error, malformed response: PASS")
