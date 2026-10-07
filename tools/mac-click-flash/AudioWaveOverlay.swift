import AppKit

final class AudioWaveOverlay {
    private var panels: [NSPanel] = []
    private var whitePanels: [NSPanel] = []
    private var hideTimer: Timer?
    private var whiteTimer: Timer?
    private var animationTimer: Timer?
    private(set) var animationFrames = 0

    func receiving() {
        show(samples: [], label: "RECEIVING AUDIO…")
        whiteTimer?.invalidate()
        whitePanels.forEach { $0.close() }
        whitePanels = NSScreen.screens.map { screen in
            let panel = makePanel(screen.frame)
            panel.backgroundColor = .white
            panel.orderFrontRegardless()
            return panel
        }
        whiteTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: false) { [weak self] _ in
            self?.whitePanels.forEach { $0.orderOut(nil) }
        }
    }

    @discardableResult func showWav(_ url: URL) throws -> Int {
        let data = try Data(contentsOf: url)
        guard data.count >= 44, String(data: data.prefix(4), encoding: .ascii) == "RIFF",
              String(data: data[36..<40], encoding: .ascii) == "data",
              data[20] == 1, data[22] == 1, data[34] == 16 else { throw CocoaError(.fileReadCorruptFile) }
        let bytes = Array(data.dropFirst(44))
        let samples = stride(from: 0, to: bytes.count - bytes.count % 2, by: 2).map {
            Int16(bitPattern: UInt16(bytes[$0]) | UInt16(bytes[$0+1]) << 8)
        }
        show(samples: samples, label: String(format: "AUDIO  %.2f s  ·  8 kHz", Double(samples.count)/8000))
        hideTimer = Timer.scheduledTimer(withTimeInterval: 20, repeats: false) { [weak self] _ in self?.clear() }
        return samples.count
    }

    private func show(samples: [Int16], label: String) {
        hideTimer?.invalidate()
        animationTimer?.invalidate()
        panels.forEach { $0.close() }
        panels = NSScreen.screens.map { screen in
            let width = min(1000, screen.visibleFrame.width * 0.8)
            let frame = NSRect(x: screen.visibleFrame.midX-width/2, y: screen.visibleFrame.minY+35, width: width, height: 180)
            let panel = makePanel(frame)
            panel.contentView = AudioWaveView(frame: NSRect(origin: .zero, size: frame.size), samples: samples, label: label)
            panel.orderFrontRegardless()
            return panel
        }
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.animationFrames += 1
            self.panels.forEach { $0.contentView?.needsDisplay = true }
        }
        animationTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    private func makePanel(_ frame: NSRect) -> NSPanel {
        let panel = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.level = .screenSaver
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
    func clear() {
        hideTimer?.invalidate()
        whiteTimer?.invalidate()
        animationTimer?.invalidate()
        animationTimer = nil
        panels.forEach { $0.orderOut(nil) }
        whitePanels.forEach { $0.orderOut(nil) }
    }
}

private final class AudioWaveView: NSView {
    let samples: [Int16]
    let label: String
    private let started = ProcessInfo.processInfo.systemUptime
    private let peak: Int
    init(frame: NSRect, samples: [Int16], label: String) {
        self.samples = samples; self.label = label
        peak = max(2048, samples.map { abs(Int($0)) }.max() ?? 0)
        super.init(frame: frame)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func draw(_ dirtyRect: NSRect) {
        NSColor(calibratedRed: 0.01, green: 0.06, blue: 0.04, alpha: 0.22).setFill()
        bounds.fill()
        let grid = NSBezierPath()
        for i in 0...10 {
            let x = bounds.width * CGFloat(i)/10
            grid.move(to: NSPoint(x:x,y:0)); grid.line(to:NSPoint(x:x,y:bounds.height))
        }
        for i in 0...4 {
            let y = bounds.height * CGFloat(i)/4
            grid.move(to:NSPoint(x:0,y:y)); grid.line(to:NSPoint(x:bounds.width,y:y))
        }
        NSColor(calibratedRed: 0.08, green: 0.24, blue: 0.17, alpha: 0.45).setStroke()
        grid.stroke()
        let green = NSColor(calibratedRed: 0.37, green: 1, blue: 0.61, alpha: 0.85)
        (label as NSString).draw(at: NSPoint(x:14,y:bounds.height-30), withAttributes: [.font:NSFont.monospacedSystemFont(ofSize:16,weight:.medium), .foregroundColor:green])
        let center = bounds.height * 0.44
        let scale = bounds.height * 0.30 / CGFloat(peak)
        let columns = max(1, Int(bounds.width))
        let duration = max(1.2, min(6, Double(samples.count) / 8000))
        let elapsed = ProcessInfo.processInfo.systemUptime - started
        let phase = CGFloat(elapsed.truncatingRemainder(dividingBy: duration) / duration)
        // A moving beam redraws the actual recording; exponential decay gives phosphor persistence.
        let traces = (0..<16).map { _ in NSBezierPath() }
        for x in 0..<columns {
            let position = CGFloat(x) / CGFloat(columns)
            let age = (phase - position + 1).truncatingRemainder(dividingBy: 1)
            let brightness = 0.08 + 0.92 * exp(-age * 5)
            let bucket = min(15, Int(brightness * 15))
            let line = traces[bucket]
            if samples.isEmpty {
                line.move(to:NSPoint(x:CGFloat(x),y:center))
                line.line(to:NSPoint(x:CGFloat(x+1),y:center))
            } else {
                let start = x*samples.count/columns
                let end = min(samples.count, max(start+1,(x+1)*samples.count/columns))
                var lo = 32767; var hi = -32768
                for i in start..<end { lo = min(lo,Int(samples[i])); hi = max(hi,Int(samples[i])) }
                line.move(to:NSPoint(x:CGFloat(x),y:center+CGFloat(lo)*scale))
                line.line(to:NSPoint(x:CGFloat(x),y:center+CGFloat(hi)*scale))
            }
        }
        NSGraphicsContext.saveGraphicsState()
        let glow = NSShadow(); glow.shadowBlurRadius = 5
        glow.shadowColor = green.withAlphaComponent(0.45); glow.set()
        for (index, line) in traces.enumerated() {
            line.lineWidth = 1.3
            green.withAlphaComponent(0.12 + 0.75 * CGFloat(index)/15).setStroke()
            line.stroke()
        }
        let beam = NSBezierPath(); beam.lineWidth = 1
        beam.move(to:NSPoint(x:phase*bounds.width,y:12))
        beam.line(to:NSPoint(x:phase*bounds.width,y:bounds.height-38))
        green.withAlphaComponent(0.45).setStroke(); beam.stroke()
        NSGraphicsContext.restoreGraphicsState()
    }
}
