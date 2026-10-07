import Foundation
import CoreBluetooth

final class AudioReceiver: NSObject, CBPeripheralDelegate {
    static let serviceID = CBUUID(string: "18424398-7cbc-11e9-8f9e-2a86e4085a59")
    static let controlID = CBUUID(string: "2d86686a-53dc-25b3-0c4a-f0e10c8dee20")
    static let audioID = CBUUID(string: "2d86686a-53dc-25b3-0c4a-f0e10c8dee21")
    let peripheral: CBPeripheral
    private let central: CBCentralManager
    private let folder: URL
    private let log: (String, [String: Any]) -> Void
    private let completed: (URL?) -> Void
    private var control: CBCharacteristic?
    private var audio: CBCharacteristic?
    private var expectedSamples = 0
    private var received = Data()
    private var rawFile: FileHandle?
    private var rawURL: URL?
    private var timeout: Timer?
    private var finished = false

    init(peripheral: CBPeripheral, central: CBCentralManager, folder: URL,
         log: @escaping (String, [String: Any]) -> Void, completed: @escaping (URL?) -> Void) {
        self.peripheral = peripheral
        self.central = central
        self.folder = folder
        self.log = log
        self.completed = completed
        super.init()
    }

    static func advertisedSamples(_ data: Data) -> Int {
        let b = Array(data)
        guard b.count >= 7, b[0] == 0xff, b[1] == 0xff else { return 0 }
        return Int(b[5]) | (Int(b[6]) << 8)
    }

    func start() {
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            // Open the backup before asking the ring to send: it releases delivered clips.
            let stamp = DateFormatter()
            stamp.dateFormat = "yyyyMMdd-HHmmss-SSS"
            let url = folder.appendingPathComponent("pebble-\(stamp.string(from: Date()))-\(UUID().uuidString.prefix(4)).adpcm")
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            rawURL = url
            rawFile = try FileHandle(forWritingTo: url)
        } catch { fail("保存先を準備できません: \(error)"); return }
        peripheral.delegate = self
        timeout = Timer.scheduledTimer(withTimeInterval: 120, repeats: false) { [weak self] _ in
            self?.fail("音声転送がタイムアウトしました")
        }
        log("audio-connect", ["device": peripheral.identifier.uuidString])
        central.connect(peripheral, options: nil)
    }

    func connected() { peripheral.discoverServices([Self.serviceID]) }
    func disconnected(error: Error?) {
        if !finished { fail("音声転送中に切断されました: \(error?.localizedDescription ?? "connection closed")") }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        if let error { fail("サービス検出: \(error)"); return }
        guard let service = peripheral.services?.first(where: { $0.uuid == Self.serviceID }) else {
            fail("CFWの音声サービスがありません"); return
        }
        peripheral.discoverCharacteristics([Self.controlID, Self.audioID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        if let error { fail("キャラクタリスティック検出: \(error)"); return }
        control = service.characteristics?.first { $0.uuid == Self.controlID }
        audio = service.characteristics?.first { $0.uuid == Self.audioID }
        guard let control, audio != nil else { fail("音声キャラクタリスティックがありません"); return }
        peripheral.setNotifyValue(true, for: control)
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail("通知の購読: \(error)"); return }
        guard characteristic.isNotifying else { fail("通知を有効にできませんでした"); return }
        if characteristic.uuid == Self.controlID, let audio {
            peripheral.setNotifyValue(true, for: audio)
        } else if characteristic.uuid == Self.audioID, let control {
            // The firmware clamps this to its negotiated ATT MTU; CoreBluetooth handles negotiation.
            peripheral.writeValue(Data([0x01, 0xf4, 0x00]), for: control, type: .withResponse)
            log("audio-request", ["chunk": 244])
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: Error?) {
        if let error { fail("転送要求: \(error)") }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        guard !finished else { return }
        if let error { fail("音声受信: \(error)"); return }
        guard let value = characteristic.value else { fail("通知が空です"); return }
        if characteristic.uuid == Self.controlID {
            let bytes = Array(value)
            if bytes.count == 3, bytes[0] == 0x01 {
                guard expectedSamples == 0, received.isEmpty else { fail("開始通知が重複しています"); return }
                expectedSamples = Int(bytes[1]) | (Int(bytes[2]) << 8)
                guard expectedSamples > 0, expectedSamples <= AudioCodec.maxSamples else { fail("サンプル数が不正です"); return }
                log("audio-start", ["samples": expectedSamples, "seconds": Double(expectedSamples) / 8000])
                do {
                    if let rawURL {
                        let meta = try JSONSerialization.data(withJSONObject: ["samples": expectedSamples, "rate": 8000])
                        try meta.write(to: rawURL.appendingPathExtension("json"), options: .atomic)
                    }
                } catch { fail("録音情報を保存できません: \(error)") }
            } else if bytes == [0x02] {
                saveRecording()
            } else { fail("不明な転送通知です") }
        } else if characteristic.uuid == Self.audioID {
            guard expectedSamples > 0, !value.isEmpty,
                  received.count + value.count <= (expectedSamples + 1) / 2 else {
                fail("音声パケットの長さが不正です"); return
            }
            do { try rawFile?.write(contentsOf: value) }
            catch { fail("音声を書き込めません: \(error)"); return }
            received.append(value)
        }
    }

    private func saveRecording() {
        do {
            let wav = try AudioCodec.wav(adpcm: received, samples: expectedSamples)
            guard let rawURL else { throw CocoaError(.fileWriteUnknown) }
            try rawFile?.synchronize()
            let destination = rawURL.deletingPathExtension().appendingPathExtension("wav")
            try wav.write(to: destination, options: .atomic)
            log("audio-saved", ["path": destination.path, "samples": expectedSamples,
                                "bytes": received.count, "seconds": Double(expectedSamples) / 8000])
            finish(destination)
        } catch { fail("録音保存に失敗しました: \(error)") }
    }

    private func fail(_ message: String) {
        guard !finished else { return }
        log("audio-error", ["message": message, "bytes": received.count])
        finish(nil)
    }

    private func finish(_ file: URL?) {
        guard !finished else { return }
        finished = true
        timeout?.invalidate()
        try? rawFile?.close()
        rawFile = nil
        if peripheral.state != .disconnected { central.cancelPeripheralConnection(peripheral) }
        completed(file)
    }
}
