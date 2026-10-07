import AppKit
import QuartzCore

final class CommentOverlay {
    private var windows: [NSPanel] = []
    private var available: [TimeInterval] = Array(repeating: 0, count: 5)
    private var nextLane = 0
    var activeCommentCount: Int { windows.first?.contentView?.layer?.sublayers?.count ?? 0 }

    init() { rebuild() }

    func rebuild() {
        windows.forEach { $0.close() }
        windows = NSScreen.screens.map { screen in
            let panel = NSPanel(contentRect: screen.frame, styleMask: [.borderless, .nonactivatingPanel],
                                backing: .buffered, defer: false)
            panel.isReleasedWhenClosed = false
            panel.level = .screenSaver
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.ignoresMouseEvents = true
            panel.hidesOnDeactivate = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            let view = NSView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.wantsLayer = true
            view.layer?.masksToBounds = true
            panel.contentView = view
            return panel
        }
        available = Array(repeating: 0, count: 5)
    }

    @discardableResult
    func show(_ text: String) -> [String: Any] {
        let now = CACurrentMediaTime()
        let lane = (0..<5).map { (nextLane + $0) % 5 }.first { available[$0] <= now }
            ?? available.indices.min(by: { available[$0] < available[$1] })!
        nextLane = (lane + 1) % 5
        let delay = max(0, available[lane] - now)
        var longest: TimeInterval = 0
        for panel in windows {
            guard let view = panel.contentView, let root = view.layer else { continue }
            let fontSize = max(56, min(88, view.bounds.height * 0.065))
            let layer = Self.textLayer(text, fontSize: fontSize, scale: panel.screen?.backingScaleFactor ?? 2)
            let width = layer.bounds.width
            let start = view.bounds.width + width / 2 + 24
            let end = -width / 2 - 24
            let duration = TimeInterval((start - end) / 260)
            longest = max(longest, duration)
            let y = view.bounds.height * (0.22 + Double(lane) * 0.135)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = CGPoint(x: end, y: y)
            root.addSublayer(layer)
            CATransaction.commit()
            let animation = CABasicAnimation(keyPath: "position.x")
            animation.fromValue = start
            animation.toValue = end
            animation.duration = duration
            animation.beginTime = now + delay
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            animation.fillMode = .both
            animation.isRemovedOnCompletion = false
            layer.add(animation, forKey: "scroll")
            panel.orderFrontRegardless()
            DispatchQueue.main.asyncAfter(deadline: .now() + delay + duration + 0.1) {
                layer.removeFromSuperlayer()
            }
        }
        available[lane] = now + delay + longest + 0.25
        return ["text": text, "lane": lane, "seconds": longest, "delay": delay, "screens": windows.count]
    }

    func clear() {
        windows.forEach {
            $0.contentView?.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
            $0.orderOut(nil)
        }
        available = Array(repeating: 0, count: 5)
    }

    // Render our own text layer for layout QA, without capturing the user's screen.
    static func preview(_ text: String, to url: URL) throws {
        guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 1440, pixelsHigh: 900,
                                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                          isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return }
        let root = CALayer()
        root.bounds = CGRect(x: 0, y: 0, width: 1440, height: 900)
        root.backgroundColor = NSColor(calibratedRed: 0.13, green: 0.16, blue: 0.23, alpha: 1).cgColor
        for (index, line) in [text, "声がコメントになって流れる！"].enumerated() {
            let layer = textLayer(line, fontSize: 72, scale: 1)
            layer.position = CGPoint(x: 720, y: 590 - CGFloat(index) * 170)
            root.addSublayer(layer)
        }
        root.render(in: context.cgContext)
        if let png = bitmap.representation(using: .png, properties: [:]) { try png.write(to: url) }
    }

    private static func textLayer(_ text: String, fontSize: CGFloat, scale: CGFloat) -> CATextLayer {
        let string = NSAttributedString(string: text, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
            .foregroundColor: NSColor.white,
            .strokeColor: NSColor.black,
            .strokeWidth: -4.0,
        ])
        let layer = CATextLayer()
        layer.string = string
        layer.alignmentMode = .center
        layer.isWrapped = false
        layer.contentsScale = scale
        layer.bounds = CGRect(x: 0, y: 0, width: ceil(string.size().width) + 48, height: ceil(fontSize * 1.65))
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.85
        layer.shadowRadius = 3
        layer.shadowOffset = CGSize(width: 0, height: -3)
        return layer
    }
}
