import AppKit
import BarnCore
import StatusItemKit

/// The visible control: a narrow status item showing which way the barn is
/// drawn, carrying the menu.
///
/// Narrow on purpose. A status item only renders when its slot fits entirely
/// within the usable area, so the control has to be small enough to sit beside
/// the user's own icons — which is exactly why it cannot also be the wall.
final class Handle {
    private let controller: StatusItemController

    init(controller: StatusItemController) {
        self.controller = controller
    }

    func draw(hidden: Bool, style: HandleStyle) {
        switch style {
        case .barn: controller.setIcon(Self.barn(open: !hidden))
        case .chevron: controller.setIcon(Self.chevron(pointingLeft: hidden))
        }
    }

    /// A barn. Doors shut while the icons are hidden, open — the doorway cut
    /// out so the bar shows through — while the icons are revealed. Drawn on
    /// its own 26x22 canvas, deliberately bigger than the chevron's 18pt one:
    /// the characters are meant to have come out of it. The status item is
    /// variable-length, so the bar re-measures when the style switches.
    private static func barn(open: Bool) -> NSImage {
        let size = NSSize(width: 26, height: 22)
        let image = NSImage(size: size, flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current else { return false }
            // Barn red, drawn in colour rather than as a template: a barn is not
            // an abstract glyph, and the doorway and window stay cut-outs.
            Self.barnRed.set()
            let body = NSBezierPath()
            body.move(to: NSPoint(x: 2, y: 1)); body.line(to: NSPoint(x: 2, y: 10.5))
            body.line(to: NSPoint(x: 5, y: 16)); body.line(to: NSPoint(x: 13, y: 21)); body.line(to: NSPoint(x: 21, y: 16))
            body.line(to: NSPoint(x: 24, y: 10.5)); body.line(to: NSPoint(x: 24, y: 1)); body.close()
            body.fill()
            // Doorway and hayloft window are holes.
            ctx.compositingOperation = .destinationOut
            NSBezierPath(roundedRect: NSRect(x: 9.3, y: 1, width: 7.4, height: 8.6), xRadius: 0.8, yRadius: 0.8).fill()
            NSBezierPath(ovalIn: NSRect(x: 11.4, y: 12.4, width: 3.2, height: 3.2)).fill()
            ctx.compositingOperation = .sourceOver
            if !open {
                NSBezierPath(rect: NSRect(x: 10, y: 1, width: 6, height: 7.9)).fill()
                ctx.compositingOperation = .destinationOut
                let seam = NSBezierPath()
                seam.move(to: NSPoint(x: 13, y: 1)); seam.line(to: NSPoint(x: 13, y: 8.9))
                seam.lineWidth = 0.9; seam.stroke()
                ctx.compositingOperation = .sourceOver
            }
            return true
        }
        image.isTemplate = false
        return image
    }

    private static let barnRed = NSColor(red: 0.64, green: 0.21, blue: 0.17, alpha: 1)

    /// A chevron stroked as a path, matching how `MeterIcon` draws across these
    /// apps. Points the way the icons will go when clicked.
    private static func chevron(pointingLeft: Bool) -> NSImage {
        let side: CGFloat = 18
        let arm: CGFloat = 4.5
        let rise: CGFloat = 4.5

        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            let midX = rect.midX
            let midY = rect.midY
            let path = NSBezierPath()
            if pointingLeft {
                path.move(to: NSPoint(x: midX + arm / 2, y: midY + rise))
                path.line(to: NSPoint(x: midX - arm / 2, y: midY))
                path.line(to: NSPoint(x: midX + arm / 2, y: midY - rise))
            } else {
                path.move(to: NSPoint(x: midX - arm / 2, y: midY + rise))
                path.line(to: NSPoint(x: midX + arm / 2, y: midY))
                path.line(to: NSPoint(x: midX - arm / 2, y: midY - rise))
            }
            path.lineWidth = 1.8
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            // Template tinting keys off alpha, so the ink colour is irrelevant.
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }
}
