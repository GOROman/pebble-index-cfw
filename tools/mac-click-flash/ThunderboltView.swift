import AppKit

final class ThunderboltView: NSView {
    override func draw(_ dirtyRect: NSRect) {
        // Four pixel-edged wedges converge at the center, matching the supplied reference.
        NSColor(calibratedRed: 1, green: 0.72, blue: 0, alpha: 0.12).setFill()
        bounds.fill()
        let wedge: [(CGFloat, CGFloat)] = [(0.465,0.465),(0,0.07),(0,0.31),(0.195,0.395),(0.195,0.31)]
        NSColor(calibratedRed: 1, green: 0.96, blue: 0, alpha: 1).setFill()
        for mirrorX in [false, true] {
            for mirrorY in [false, true] {
                let path = NSBezierPath()
                for (index, point) in wedge.enumerated() {
                    let x = (mirrorX ? 1-point.0 : point.0) * bounds.width
                    let y = (mirrorY ? 1-point.1 : point.1) * bounds.height
                    if index == 0 { path.move(to: NSPoint(x:x,y:y)) }
                    else { path.line(to: NSPoint(x:x,y:y)) }
                }
                path.close()
                path.fill()
            }
        }
    }
}
