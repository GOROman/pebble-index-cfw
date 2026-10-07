import AppKit
import CoreBluetooth

func option(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: name),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

final class ClickFlashApp: NSObject, NSApplicationDelegate, CBCentralManagerDelegate {
    private var central: CBCentralManager?
    private var statusItem: NSStatusItem!
    private let statusLine = NSMenuItem(title: "Bluetoothを準備中…", action: nil, keyEquivalent: "")
    private let ringLine = NSMenuItem(title: "リング未検出", action: nil, keyEquivalent: "")
    private var pauseItem: NSMenuItem!
    private var overlays: [NSPanel] = []
    private var hideTimer: Timer?
    private var counter = ClickCounter()
    private var selectedDevice: UUID?
    private var paused = false
    private var flashes = 0
    private var logFile: FileHandle?
    private let audioLine = NSMenuItem(title: "音声: 長押しして録音", action: nil, keyEquivalent: "")
    private var audioReceiver: AudioReceiver?
    private var audioRetryAfter = Date.distantPast
    private var lastRecording: URL?
    private var playback: NSSound?
    private var clickSound = NSSound(contentsOf: Bundle.main.url(forResource: "thunder", withExtension: "wav") ?? URL(fileURLWithPath: "/dev/null"), byReference: false)
    private var soundMuted = false
    private var soundItem: NSMenuItem!
    private var playItem: NSMenuItem!
    private let speechLine = NSMenuItem(title: "STT: 日本語・ローカル認識", action: nil, keyEquivalent: "")
    private var comments: CommentOverlay!
    private var speech: SpeechPipeline!
    private var recordingsFolder: URL {
        if let path = option("--recordings") { return URL(fileURLWithPath: path, isDirectory: true) }
        return Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("recordings", isDirectory: true)
    }
    private let selfTest = CommandLine.arguments.contains("--self-test")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        if let path = option("--log") {
            if !FileManager.default.fileExists(atPath: path) {
                FileManager.default.createFile(atPath: path, contents: nil)
            }
            logFile = FileHandle(forWritingAtPath: path)
            logFile?.seekToEndOfFile()
        }
        if let raw = option("--device") {
            guard let id = UUID(uuidString: raw) else {
                log("error", ["message": "Invalid --device UUID"])
                NSApp.terminate(nil)
                return
            }
            selectedDevice = id
        }
        buildMenu()
        rebuildOverlays()
        comments = CommentOverlay()
        let root = Bundle.main.bundleURL.deletingLastPathComponent()
        let model = option("--model") ?? root.appendingPathComponent("models/ggml-small.bin").path
        let ffmpeg = option("--ffmpeg") ?? "/opt/homebrew/bin/ffmpeg"
        let whisper = option("--whisper") ?? "/opt/homebrew/bin/whisper-cli"
        speech = SpeechPipeline(model: URL(fileURLWithPath: model), ffmpeg: URL(fileURLWithPath: ffmpeg),
                                whisper: URL(fileURLWithPath: whisper))
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged),
            name: NSApplication.didChangeScreenParametersNotification, object: nil
        )
        log("started", ["selfTest": selfTest, "device": selectedDevice?.uuidString ?? "auto"])
        if let text = option("--demo-comment") {
            if let preview = option("--preview") { try? CommentOverlay.preview(text, to: URL(fileURLWithPath: preview)) }
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in self?.showComment(text) }
            Timer.scheduledTimer(withTimeInterval: 1.4, repeats: false) { [weak self] _ in self?.showComment("声がコメントになって流れる！") }
            Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in NSApp.terminate(nil) }
        } else if let file = option("--transcribe-file") {
            transcribe(URL(fileURLWithPath: file), quitAfter: true)
        } else if selfTest {
            Timer.scheduledTimer(withTimeInterval: 0.5, repeats: false) { [weak self] _ in
                self?.flash(source: "self-test", clicks: 1)
            }
            Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in NSApp.terminate(nil) }
        } else {
            central = CBCentralManager(delegate: self, queue: .main)
            if let text = option("--startup-comment") {
                Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [weak self] _ in self?.showComment(text) }
            }
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "bolt.circle", accessibilityDescription: "Pebble Click Flash")
        let menu = NSMenu()
        statusLine.isEnabled = false
        ringLine.isEnabled = false
        menu.addItem(statusLine)
        menu.addItem(ringLine)
        audioLine.isEnabled = false
        menu.addItem(audioLine)
        speechLine.isEnabled = false
        menu.addItem(speechLine)
        menu.addItem(.separator())
        pauseItem = NSMenuItem(title: "一時停止", action: #selector(togglePause), keyEquivalent: "")
        pauseItem.target = self
        menu.addItem(pauseItem)
        soundItem = NSMenuItem(title: "効果音をミュート", action: #selector(toggleSound), keyEquivalent: "")
        soundItem.target = self
        menu.addItem(soundItem)
        let test = NSMenuItem(title: "フラッシュをテスト", action: #selector(testFlash), keyEquivalent: "")
        test.target = self
        menu.addItem(test)
        let commentTest = NSMenuItem(title: "コメント表示をテスト", action: #selector(testComment), keyEquivalent: "")
        commentTest.target = self
        menu.addItem(commentTest)
        playItem = NSMenuItem(title: "最新の録音を再生", action: #selector(playRecording), keyEquivalent: "")
        playItem.target = self
        playItem.isEnabled = false
        menu.addItem(playItem)
        let folder = NSMenuItem(title: "録音フォルダを開く", action: #selector(openRecordings), keyEquivalent: "")
        folder.target = self
        menu.addItem(folder)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "終了", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    @objc private func screensChanged() {
        rebuildOverlays()
        comments?.rebuild()
    }

    private func rebuildOverlays() {
        hideTimer?.invalidate()
        overlays.forEach { $0.close() }
        overlays = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.contentView = ThunderboltView(frame: NSRect(origin: .zero, size: screen.frame.size))
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.alphaValue = 0
            return panel
        }
    }

    private func flash(source: String, clicks: Int) {
        guard !paused else {
            log("paused-click", ["clicks": clicks])
            return
        }
        hideTimer?.invalidate()
        overlays.forEach {
            $0.alphaValue = 1
            $0.orderFrontRegardless()
        }
        flashes += 1
        if !soundMuted {
            clickSound?.stop()
            let played = clickSound?.play() ?? false
            log("flash-sound", ["played": played, "name": "thunder"])
        }
        log("flash", ["source": source, "clicks": clicks, "screens": overlays.count, "total": flashes])
        // Timed lightning bursts keep the main run loop available for BLE and comments.
        let brightness: [CGFloat] = [0, 1, 0.35, 0]
        var step = 0
        hideTimer = Timer.scheduledTimer(withTimeInterval: 0.055, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.overlays.forEach { $0.alphaValue = brightness[step] }
            step += 1
            if step == brightness.count {
                timer.invalidate()
                self.log("flash-complete", ["pulses": 2])
            }
        }
    }

    @objc private func togglePause() {
        paused.toggle()
        pauseItem.title = paused ? "再開" : "一時停止"
        statusItem.button?.appearsDisabled = paused
        if paused {
            hideTimer?.invalidate()
            overlays.forEach { $0.alphaValue = 0 }
            comments.clear()
        }
        log("pause", ["paused": paused])
    }

    @objc private func testFlash() { flash(source: "menu-test", clicks: 1) }
    @objc private func toggleSound() {
        soundMuted.toggle()
        soundItem.title = soundMuted ? "効果音をオン" : "効果音をミュート"
        if soundMuted { clickSound?.stop() }
        log("sound-mute", ["muted": soundMuted])
    }
    @objc private func testComment() { showComment("ニコニコ風コメント、動いてます！") }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func openRecordings() {
        try? FileManager.default.createDirectory(at: recordingsFolder, withIntermediateDirectories: true)
        NSWorkspace.shared.open(recordingsFolder)
    }
    @objc private func playRecording() {
        guard let lastRecording else { return }
        playback?.stop()
        playback = NSSound(contentsOf: lastRecording, byReference: true)
        playback?.play()
    }

    private func showComment(_ text: String) {
        guard !paused, !text.isEmpty else { return }
        log("comment-shown", comments.show(text))
    }

    private func transcribe(_ recording: URL, quitAfter: Bool = false) {
        log("stt-queued", ["path": recording.path])
        speech.transcribe(recording, status: { [weak self] status in
            self?.speechLine.title = "STT: \(status)"
        }) { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let output):
                self.log("stt-result", ["text": output.text, "seconds": output.elapsed,
                                        "cleaned": output.cleanedAudio.path, "transcript": output.transcript.path])
                if output.text.isEmpty {
                    self.speechLine.title = "STT: 発話を認識できませんでした"
                } else {
                    self.speechLine.title = "STT: \(String(output.text.prefix(35)))"
                    self.showComment(output.text)
                }
            case .failure(let error):
                self.speechLine.title = "STT: \(error.localizedDescription)"
                self.log("stt-error", ["message": error.localizedDescription])
            }
            if quitAfter {
                Timer.scheduledTimer(withTimeInterval: 12, repeats: false) { _ in NSApp.terminate(nil) }
            }
        }
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusLine.title = "クリック待ち（BLEスキャン中）"
            central.scanForPeripherals(withServices: nil,
                                      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true])
            log("scanning")
        case .unauthorized:
            statusLine.title = "システム設定でBluetoothを許可してください"
            log("bluetooth-unauthorized")
        case .poweredOff:
            statusLine.title = "Bluetoothをオンにしてください"
            log("bluetooth-off")
        default:
            statusLine.title = "Bluetoothを準備中…"
            log("bluetooth-state", ["state": central.state.rawValue])
        }
    }

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral,
                        advertisementData: [String: Any], rssi RSSI: NSNumber) {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              let value = ClickCounter.parse(data) else { return }
        if let selectedDevice {
            guard peripheral.identifier == selectedDevice else { return }
        } else {
            let name = advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? peripheral.name ?? ""
            guard name == "Pebble Index CFW" else { return }
            selectedDevice = peripheral.identifier
        }
        let first = counter.previous == nil
        let clicks = counter.consume(value)
        ringLine.title = "Pebble Index CFW · \(RSSI) dBm · count \(value)"
        statusItem.button?.toolTip = ringLine.title
        if first {
            log("ring-found", ["device": peripheral.identifier.uuidString, "counter": Int(value), "rssi": RSSI.intValue])
        }
        if clicks > 0 {
            log("click", ["counter": Int(value), "delta": clicks, "rssi": RSSI.intValue,
                          "activeComments": comments.activeCommentCount])
            flash(source: "ble", clicks: clicks)
        }
        let samples = AudioReceiver.advertisedSamples(data)
        if samples > 0, !paused, audioReceiver == nil, Date() >= audioRetryAfter {
            audioLine.title = "音声: 受信中…"
            let receiver = AudioReceiver(peripheral: peripheral, central: central, folder: recordingsFolder,
                                         log: { [weak self] event, fields in self?.log(event, fields) }) { [weak self] url in
                guard let self else { return }
                self.audioRetryAfter = Date().addingTimeInterval(url == nil ? 20 : 2)
                if let url {
                    self.lastRecording = url
                    self.playItem.isEnabled = true
                    self.audioLine.title = "音声: 保存しました（\(url.lastPathComponent)）"
                    self.transcribe(url)
                } else {
                    self.audioLine.title = "音声: 取得失敗（20秒後に再試行）"
                }
                // Keep the receiver alive until CoreBluetooth confirms disconnect.
                if peripheral.state == .disconnected { self.audioReceiver = nil }
            }
            audioReceiver = receiver
            receiver.start()
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        if audioReceiver?.peripheral.identifier == peripheral.identifier { audioReceiver?.connected() }
    }
    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        audioReceiver?.disconnected(error: error)
        audioReceiver = nil
    }
    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        audioReceiver?.disconnected(error: error)
        audioReceiver = nil
    }

    private func log(_ event: String, _ fields: [String: Any] = [:]) {
        var record = fields
        record["event"] = event
        record["time"] = ISO8601DateFormatter().string(from: Date())
        guard var data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        data.append(0x0a)
        FileHandle.standardOutput.write(data)
        logFile?.write(data)
    }

    func applicationWillTerminate(_ notification: Notification) {
        central?.stopScan()
        hideTimer?.invalidate()
        overlays.forEach { $0.orderOut(nil) }
        comments?.clear()
        log("stopped")
        try? logFile?.close()
    }
}

let app = NSApplication.shared
let delegate = ClickFlashApp()
app.delegate = delegate
app.run()
